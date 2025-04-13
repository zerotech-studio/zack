const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const Bar = common.Bar;
const csv = @import("../utils/csv/csv-parser.zig"); // To reference csv.Table if needed, but we just need the body

// Manages providing bars of data sequentially from the loaded CSV data.
pub const DataHandler = struct {
    allocator: Allocator,
    all_rows: std.ArrayList([]const u8), // Reference to the CSV body rows
    current_index: usize,

    // Initializes the DataHandler with the raw CSV data rows.
    // Takes ownership or reference to the rows depending on how AppContext manages it.
    // Currently, AppContext keeps the buffer alive, so we just reference the ArrayList.
    pub fn init(alloc: Allocator, rows: std.ArrayList([]const u8)) DataHandler {
        return DataHandler{
            .allocator = alloc,
            .all_rows = rows,
            .current_index = 0,
        };
    }

    // Fetches and parses the next bar from the data.
    // Returns null if there are no more bars or if the next row fails to parse.
    // Uses an ArenaAllocator for temporary allocations during parsing.
    pub fn nextBar(self: *DataHandler) !?Bar {
        if (self.current_index >= self.all_rows.items.len) {
            return null; // No more data
        }

        // Use a temporary ArenaAllocator for parsing each row
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();

        const row_str = self.all_rows.items[self.current_index];
        self.current_index += 1;

        // Try parsing the row
        const maybe_bar = Bar.parse(row_str, temp_allocator) catch |err| {
            // Log or handle allocation errors during parsing if necessary
            std.debug.print("ERROR: Allocation error during Bar.parse: {s}\n", .{@errorName(err)});
            return error.ParsingAllocationError; // Propagate allocation errors
        };

        if (maybe_bar == null) {
            // Parsing failed (e.g., bad format, wrong field count), warning printed inside Bar.parse
            // Optionally log here too, or decide to retry/skip
            // For now, we just return null, effectively skipping the bad row.
            // To distinguish between end-of-data and bad row, the loop calling this
            // might need to check the index or we could return an error enum.
            // Let's try fetching the *next* valid bar instead of returning null immediately.
            return self.nextBar(); // Recursive call to get the next *valid* one
            // WARNING: Recursive call could lead to stack overflow on large chunks of bad data.
            // An iterative approach would be safer.
            // TODO: Refactor to iterative loop to find next valid bar.
        }

        return maybe_bar.?;
    }

    // Resets the handler to the beginning of the data stream.
    pub fn reset(self: *DataHandler) void {
        self.current_index = 0;
    }
};

// TODO: Add test cases for DataHandler
