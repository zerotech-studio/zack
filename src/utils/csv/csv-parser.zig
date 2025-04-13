//! This module provides structs for parsing and manipulating CSV data
//! [Released under GNU LGPLv3]
//!
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const TableIterator = @import("iterators.zig").TableIterator;
const RowIterator = @import("iterators.zig").RowIterator;
const ColumnIterator = @import("iterators.zig").ColumnIterator;

/// A structure for storing settings for use with struct Table
pub const Settings = struct {
    /// The delimiter that separates the values (aka. separator)
    delimiter: []const u8,
    /// The terminator that defines when a row of delimiter-separated values is terminated
    terminator: []const u8,

    /// A function that returns the default settings that are most commonly used for CSV data
    /// { .delimiter = ",", .terminator = "\n" }
    pub fn default() Settings {
        return Settings{
            .delimiter = ",",
            .terminator = "\n",
        };
    }
};

/// Errors that may return from struct Table
pub const TableError = error{
    /// The requested index is out of bounds
    IndexNotFound,
    /// The provided key name was not found in the header of the CSV data
    KeyNotFound,
    /// The CSV is missing a header (first row defining column keys)
    MissingHeader,
    /// A CSV row is missing a column
    MissingValue,
    /// Could not allocate required memory
    OutOfMemory,
    /// The requested row was not found
    RowNotFound,
    /// The requested value contains a delimiter or terminator character
    IllegalCharacter,
};

/// A structure for parsing and manipulating CSV data
pub const Table = struct {
    /// The settings that should be used when parsing the CSV data
    settings: Settings,
    // allocator that was first passed to initialize header and body
    // typically used when new buffer data is temporarily allocated
    allocator: Allocator,
    // allocator that will automatically be deinitialized when Table.deinit is called
    // typically used when new data for the table is allocated
    arena_allocator: std.heap.ArenaAllocator,
    // array of the names of columns, as denoted by the first row in a CSV table
    header: std.ArrayListAligned([]const u8, null),
    // array of delimiter-separated rows
    body: std.ArrayListAligned([]const u8, null),

    // Return the item with the matching index from an iterator struct std.mem.SplitIterator(T)
    fn splitIteratorGetIndex(comptime T: type, split_iterator: *std.mem.SplitIterator(T, .sequence), target_index: usize) TableError![]const T {
        var index: usize = 0;

        while (split_iterator.next()) |item| : (index += 1) {
            if (index == target_index) {
                return item;
            }
        }

        return TableError.IndexNotFound;
    }

    /// Initialize struct Table
    pub fn init(allocator: Allocator, settings: Settings) Table {
        return Table{
            .settings = settings,
            .allocator = allocator,
            .arena_allocator = std.heap.ArenaAllocator.init(allocator),
            .header = ArrayList([]const u8).init(allocator),
            .body = ArrayList([]const u8).init(allocator),
        };
    }

    /// De-initialize a struct Table, freeing its used memory
    pub fn deinit(self: *Table) void {
        self.header.deinit();
        self.body.deinit();
        self.arena_allocator.deinit();
    }

    /// Load CSV data into the struct Table
    pub fn parse(self: *Table, csv_data: []const u8) TableError!void {
        var rows = std.mem.splitSequence(u8, csv_data, self.settings.terminator);
        var header = std.mem.splitSequence(u8, rows.next() orelse return TableError.MissingHeader, self.settings.delimiter);
        var body = std.mem.splitSequence(u8, rows.rest(), self.settings.terminator);

        self.header.clearAndFree();
        self.body.clearAndFree();

        while (header.next()) |key| if (key.len > 0) try self.header.append(key);
        while (body.next()) |row| if (row.len > 0) try self.body.append(row);
    }

    /// Append row of CSV data to the struct Table
    pub fn parseRow(self: *Table, csv_row: []const u8) TableError!void {
        if (self.header.items.len == 0) {
            // assuming that csv_row is the header
            var values = std.mem.splitSequence(u8, csv_row, self.settings.delimiter);
            while (values.next()) |value| try self.header.append(value);
        } else {
            // assuming that csv_row is a row of the body
            try self.body.append(csv_row);
        }
    }

    /// Returns a slice of all column keys
    pub fn getAllColumns(self: Table) []const []const u8 {
        return self.header.items;
    }

    /// Returns a struct TableIterator containing all rows inside struct Table
    pub fn getAllRows(self: Table) TableIterator {
        return TableIterator{
            .delimiter = self.settings.delimiter,
            .header = self.header.items,
            .body = self.body.items,
        };
    }

    /// Return a slice of column indexes by provided key
    pub fn findColumnIndexesByKey(self: Table, allocator: Allocator, searched_key: []const u8) TableError![]usize {
        var column_indexes = ArrayList(usize).init(allocator);

        for (self.header.items, 0..) |current_key, index| {
            if (std.mem.eql(u8, current_key, searched_key)) {
                try column_indexes.append(index);
            }
        }

        if (column_indexes.items.len <= 0) return TableError.KeyNotFound;

        return column_indexes.toOwnedSlice();
    }

    /// Return a slice of row indexes by a provided column index and searched value
    pub fn findRowIndexesByValue(self: Table, allocator: Allocator, column_index: usize, searched_value: []const u8) TableError![]usize {
        var row_indexes = ArrayList(usize).init(allocator);

        if (column_index >= self.header.items.len) return TableError.IndexNotFound;

        for (self.body.items, 0..) |row, row_index| {
            const row_count = std.mem.count(u8, row, self.settings.delimiter) + 1;
            var row_values = std.mem.splitSequence(u8, row, self.settings.delimiter);
            if (column_index >= row_count) return TableError.MissingValue;
            const value = try Table.splitIteratorGetIndex(u8, &row_values, column_index);

            if (std.mem.eql(u8, value, searched_value)) {
                try row_indexes.append(row_index);
            }
        }

        if (row_indexes.items.len <= 0) return TableError.RowNotFound;

        return row_indexes.toOwnedSlice();
    }

    /// Returns a struct ColumnIterator, containing all elements of a given column by its index
    pub fn getColumnByIndex(self: Table, column_index: usize) ColumnIterator {
        return ColumnIterator{
            .body = self.body.items,
            .delimiter = self.settings.delimiter,
            .column_index = column_index,
        };
    }

    /// Returns a struct RowIterator, containing all values of a given row by its index
    pub fn getRowByIndex(self: *Table, row_index: usize) TableError!RowIterator {
        if (row_index >= self.body.items.len) return TableError.IndexNotFound;

        return RowIterator{
            .header = self.header.items,
            .row = std.mem.splitSequence(u8, self.body.items[row_index], self.settings.delimiter),
        };
    }

    /// Insert a new and empty row and return its index
    pub fn insertEmptyRow(self: *Table) TableError!usize {
        // create empty row with expected amount of delimiter
        var new_row = ArrayList(u8).init(self.arena_allocator.allocator());
        var i: usize = 0;
        while (i < self.header.items.len - 1) : (i += 1) {
            try new_row.appendSlice(self.settings.delimiter);
        }

        // append row to body
        try self.body.append(new_row.items);

        return self.body.items.len - 1;
    }

    /// Insert a new and empty column to all rows and return its index
    pub fn insertEmptyColumn(self: *Table, column_key: []const u8) TableError!usize {
        // check whether delimiter or terminator is in column_key
        if (std.mem.count(u8, column_key, self.settings.delimiter) != 0) return TableError.IllegalCharacter;
        if (std.mem.count(u8, column_key, self.settings.terminator) != 0) return TableError.IllegalCharacter;

        // append new column to header
        try self.header.append(column_key);

        // append new column to all rows
        const row_allocator = self.arena_allocator.allocator();

        for (self.body.items, 0..) |row, row_index| {
            self.body.items[row_index] = try std.fmt.allocPrint(row_allocator, "{s}{s}", .{ row, self.settings.delimiter });
        }

        return self.header.items.len - 1;
    }

    /// Replace a value by a given new value, row index, and column index
    pub fn replaceValue(self: *Table, row_index: usize, column_index: usize, value: []const u8) TableError!void {
        if (row_index >= self.body.items.len) return TableError.IndexNotFound;
        if (std.mem.count(u8, value, self.settings.delimiter) != 0) return TableError.IllegalCharacter;
        if (std.mem.count(u8, value, self.settings.terminator) != 0) return TableError.IllegalCharacter;

        var row_values = ArrayList([]const u8).init(self.allocator);
        defer row_values.deinit();

        var row_value_iter = std.mem.splitSequence(u8, self.body.items[row_index], self.settings.delimiter);
        while (row_value_iter.next()) |row_value| try row_values.append(row_value);

        if (column_index >= row_values.items.len) return TableError.MissingValue;
        try row_values.replaceRange(column_index, 1, &.{value});

        const new_row = try std.mem.join(self.arena_allocator.allocator(), self.settings.delimiter, row_values.items);
        try self.body.replaceRange(row_index, 1, &.{new_row});
    }

    /// Remove a column by its index and reorder table, thus all prior column indexes should be treated as invalid
    pub fn deleteColumnByIndex(self: *Table, column_index: usize) TableError!void {
        // remove column from header
        _ = self.header.orderedRemove(column_index);

        // remove column from body
        const row_allocator = self.arena_allocator.allocator();

        for (self.body.items, 0..) |row, row_index| {
            var values = ArrayList([]const u8).init(self.allocator);
            defer values.deinit();

            var value_iterator = std.mem.splitSequence(u8, row, self.settings.delimiter);
            while (value_iterator.next()) |value| try values.append(value);

            _ = values.orderedRemove(column_index);

            self.body.items[row_index] = try std.mem.join(row_allocator, self.settings.delimiter, values.items);
        }
    }

    /// Remove a row by its index and reorder table, thus all prior row indexes should be treated as invalid
    pub fn deleteRowByIndex(self: *Table, row_index: usize) TableError!void {
        _ = self.body.orderedRemove(row_index);
    }

    /// Return the stored table data in form of a CSV table
    pub fn exportCSV(self: *Table, allocator: Allocator) TableError![]const u8 {
        var csv = ArrayList(u8).init(allocator);

        // append header
        const header = try std.mem.join(allocator, self.settings.delimiter, self.header.items);
        defer allocator.free(header);
        try csv.appendSlice(header);

        // append rows
        for (self.body.items) |row| {
            if (row.len > 0) {
                try csv.appendSlice(self.settings.terminator);
                try csv.appendSlice(row);
            }
        }

        return csv.toOwnedSlice();
    }
};
