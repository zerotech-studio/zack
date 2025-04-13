const std = @import("std");
const Allocator = std.mem.Allocator;
const csv = @import("csv/csv-parser.zig");

// This struct should always match the config.json file
const Config = struct {
    budget: u64,
    strategy: []const u8,
    data: []const u8,
};

const Strat = struct {
    buyAt: u64,
};

const OHLCV = struct {
    timestamp: []const u8,
    open: f64,
    high: f64,
    low: f64,
    close: f64,
    volume: f64,
};

pub fn loadConfig(alloc: Allocator) !std.json.Parsed(Config) {
    const data = try std.fs.cwd().readFileAlloc(alloc, "config/config.json", 512);
    defer alloc.free(data);

    return std.json.parseFromSlice(Config, alloc, data, .{ .allocate = .alloc_always });
}

pub fn loadStrategySettings(alloc: Allocator, dataFile: []const u8) !std.json.Parsed(Strat) {
    const data = try std.fs.cwd().readFileAlloc(alloc, dataFile, 512);
    defer alloc.free(data);

    return std.json.parseFromSlice(Strat, alloc, data, .{ .allocate = .alloc_always });
}

pub fn loadOhlcvData(alloc: Allocator, dataFile: []const u8) !csv.Table {
    const dataFilePath = try std.fmt.allocPrint(alloc, "data/{s}", .{dataFile});
    defer alloc.free(dataFilePath);

    // Read the entire CSV file. Adjust size limit if needed.
    const csvData = try std.fs.cwd().readFileAlloc(alloc, dataFilePath, 1 * 1024 * 1024); // Max 1MB file size
    // Note: The csvData buffer MUST remain valid for the lifetime of the returned table.
    // The caller must ensure the allocator used here persists and that table.deinit()
    // is called before the allocator releases csvData's memory.
    // We are NOT freeing csvData here.

    var table = csv.Table.init(alloc, csv.Settings.default());
    // If parse fails, ensure table is deinitialized.
    errdefer table.deinit();
    try table.parse(csvData);

    // Caller owns the returned table and is responsible for calling deinit.
    // Caller also implicitly manages csvData's lifetime via the allocator.
    return table;
}

// timestamp,open,high,low,close,volume
// 2024-01-01T00:00:00Z,42000.00,42100.00,41900.00,42050.00,100.50
// 2024-01-01T01:00:00Z,42050.00,42200.00,42000.00,42150.00,120.75
// 2024-01-01T02:00:00Z,42150.00,42300.00,42100.00,42250.00,95.25
// 2024-01-01T03:00:00Z,42250.00,42400.00,42200.00,42300.00,110.30
// 2024-01-01T04:00:00Z,42300.00,42500.00,42250.00,42450.00,130.80
// 2024-01-01T05:00:00Z,42450.00,42600.00,42400.00,42550.00,105.20
// 2024-01-01T06:00:00Z,42550.00,42700.00,42500.00,42650.00,115.40
// 2024-01-01T07:00:00Z,42650.00,42800.00,42600.00,42750.00,125.60
// 2024-01-01T08:00:00Z,42750.00,42900.00,42700.00,42850.00,135.90
// 2024-01-01T09:00:00Z,42850.00,43000.00,42800.00,42900.00,145.70
// 2024-01-01T10:00:00Z,42900.00,43100.00,42850.00,43050.00,155.30
// 2024-01-01T11:00:00Z,43050.00,43200.00,43000.00,43150.00,165.80
// 2024-01-01T12:00:00Z,43150.00,43300.00,43100.00,43250.00,175.40
// 2024-01-01T13:00:00Z,43250.00,43400.00,43200.00,43350.00,185.90
// 2024-01-01T14:00:00Z,43350.00,43500.00,43300.00,43450.00,195.60
// 2024-01-01T15:00:00Z,43450.00,43600.00,43400.00,43550.00,205.30
// 2024-01-01T16:00:00Z,43550.00,43700.00,43500.00,43650.00,215.70
// 2024-01-01T17:00:00Z,43650.00,43800.00,43600.00,43750.00,225.40
// 2024-01-01T18:00:00Z,43750.00,43900.00,43700.00,43850.00,235.80
// 2024-01-01T19:00:00Z,43850.00,44000.00,43800.00,43950.00,245.60
// 2024-01-01T20:00:00Z,43950.00,44100.00,43900.00,44050.00,255.90
// 2024-01-01T21:00:00Z,44050.00,44200.00,44000.00,44150.00,265.40
// 2024-01-01T22:00:00Z,44150.00,44300.00,44100.00,44250.00,275.80
// 2024-01-01T23:00:00Z,44250.00,44400.00,44200.00,44350.00,285.30
// 2024-01-02T00:00:00Z,44350.00,44500.00,44300.00,44450.00,295.70
// 2024-01-02T01:00:00Z,44450.00,44600.00,44400.00,44550.00,305.40
// 2024-01-02T02:00:00Z,44550.00,44700.00,44500.00,44650.00,315.80
// 2024-01-02T03:00:00Z,44650.00,44800.00,44600.00,44750.00,325.60
// 2024-01-02T04:00:00Z,44750.00,44900.00,44700.00,44850.00,335.90

test "loadConfig" {
    const config = try loadConfig(std.testing.allocator);
    defer config.deinit();

    try std.testing.expectEqual(@as(u64, 10000), config.value.budget);
    try std.testing.expectEqualSlices(u8, "buy-and-hold.json", config.value.strategy);
    try std.testing.expectEqualSlices(u8, "btc.csv", config.value.data);
}

test "loadStrategySettings" {
    const strat = try loadStrategySettings(std.testing.allocator, "config/buy-and-hold.json");
    defer strat.deinit();

    try std.testing.expectEqual(@as(u64, 1000), strat.value.buyAt);
}
