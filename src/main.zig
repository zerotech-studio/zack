const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const AppContext = @import("utils/load-config.zig").AppContext;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    // Initialize the application context, loading all data
    var context = try AppContext.init(allocator);
    // Ensure all resources within the context are freed upon exiting main
    defer context.deinit();

    // Access configuration values through the context
    const budget = context.config.value.budget;
    const strategy_name = context.config.value.strategy;
    const data_file_name = context.config.value.data;

    // Access strategy settings through the context
    const buyAt = context.strategy.value.buyAt;

    // Access OHLCV data table through the context
    const table = context.ohlcvData;

    print("budget: {d}\nstrategy: {s}\ndata: {s}\n", .{ budget, strategy_name, data_file_name });
    print("Strategy settings: {s} {d}\n", .{ strategy_name, buyAt });
    print("OHLCV data (first 10 rows):\n", .{});
    var i: usize = 0;
    for (table.body.items) |row_str| {
        if (i >= 10) break; // Stop after printing 10 rows
        print("{s}\n", .{row_str});
        i += 1;
    }
}
