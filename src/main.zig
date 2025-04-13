const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const AppContext = @import("utils/load-config.zig").AppContext;
const logger = @import("utils/logger.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    // Initialize the application context, loading all data
    var context = try AppContext.init(allocator);
    // Ensure all resources within the context are freed upon exiting main
    defer context.deinit();

    // --- Logging ---
    logger.logConfig(context.config.value);
    logger.logStrategy(context.strategy.value);
    logger.logOhlcvHeader();

    // Log the first 10 rows using the pretty logger
    var i: usize = 0;
    for (context.ohlcvData.body.items) |row_str| {
        if (i >= 10) break; // Stop after logging 10 rows
        logger.logOhlcvRowPretty(row_str, allocator);
        i += 1;
    }
}
