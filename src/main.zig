const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const AppContext = @import("utils/load-config.zig").AppContext;
const logger = @import("utils/logger.zig");
const BacktestEngine = @import("engine/backtest_engine.zig").BacktestEngine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    // Initialize the application context, loading all data
    var context = try AppContext.init(allocator);
    // Ensure context resources are freed before allocator deinit
    defer context.deinit();

    // --- Log Initial Config --- (Keep this part)
    logger.logConfig(context.config.value);
    logger.logStrategy(context.strategy.value);

    // --- Initialize and Run Backtest Engine ---
    var engine = try BacktestEngine.init(allocator, &context);
    // Ensure engine resources are freed before context deinit
    defer engine.deinit();

    try engine.run();

    print("\nBacktest finished successfully.\n", .{});
}
