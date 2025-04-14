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
        while (self.current_index < self.all_rows.items.len) {
            // Use a temporary ArenaAllocator for parsing each row
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit(); // Ensure arena is deinitialized even if we continue the loop
            const temp_allocator = arena.allocator();

            const row_str = self.all_rows.items[self.current_index];
            const current_row_index = self.current_index; // Store index before potential increment
            self.current_index += 1;

            // Try parsing the row
            const maybe_bar = Bar.parse(row_str, temp_allocator) catch |err| {
                // Log or handle allocation errors during parsing if necessary
                std.debug.print("ERROR: Allocation error during Bar.parse at index {d}: {s}\n", .{ current_row_index, @errorName(err) });
                // If allocation fails, we might want to stop completely or skip.
                // Continuing the loop might lead to repeated allocation errors.
                // For now, let's skip this row like other parsing errors.
                continue; // Skip to the next iteration (next row)
            };

            if (maybe_bar == null) {
                // Parsing failed (e.g., bad format, wrong field count), warning printed inside Bar.parse
                // Log the index of the bad row for easier debugging
                std.debug.print("WARN: Skipping invalid bar data at index {d}\n", .{current_row_index});
                continue; // Skip to the next iteration (next row)
            }

            // Successfully parsed a bar
            return maybe_bar.?;
        }

        // Reached the end of the data without finding a valid bar
        return null;
    }

    // Resets the handler to the beginning of the data stream.
    pub fn reset(self: *DataHandler) void {
        self.current_index = 0;
    }
};
