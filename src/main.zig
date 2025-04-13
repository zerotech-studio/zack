const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const loadConfig = @import("utils/load-config.zig").loadConfig;
const loadStrat = @import("utils/load-config.zig").loadStrategySettings;
const loadOhlcvData = @import("utils/load-config.zig").loadOhlcvData;
const csv = @import("utils/csv/csv-parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    // defer {
    //     const leaked = gpa.deinit();
    //     if (leaked) {
    //         print("Memory leak detected!\n", .{});
    //     }
    // }

    const parsedConfig = try loadConfig(allocator);
    defer parsedConfig.deinit();

    const config = parsedConfig.value;

    const budget = config.budget;
    const strategy = config.strategy;
    const data = config.data;

    const strategyFilePath = try std.fmt.allocPrint(allocator, "config/{s}", .{strategy});
    defer allocator.free(strategyFilePath);

    const parsedStrategy = try loadStrat(allocator, strategyFilePath);
    defer parsedStrategy.deinit();

    const strat = parsedStrategy.value;

    const buyAt = strat.buyAt;

    var table = try loadOhlcvData(allocator, data);
    defer table.deinit();

    print("budget: {d}\nstrategy: {s}\ndata: {s}\n", .{ budget, strategy, data });
    print("Strategy settings: {d}\n", .{buyAt});
    print("OHLCV data (first 10 rows):\n", .{});
    var i: usize = 0;
    for (table.body.items) |row_str| {
        if (i >= 10) break; // Stop after printing 10 rows
        print("{s}\n", .{row_str});
        i += 1;
    }
}
