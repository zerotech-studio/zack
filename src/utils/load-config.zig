const std = @import("std");
const Allocator = std.mem.Allocator;
const csv = @import("csv/csv-parser.zig");

// This struct should always match the config.json file
pub const Config = struct {
    budget: u64,
    strategy: []const u8,
    data: []const u8,
};

pub const Strat = struct {
    buyAt: u64,
};

// Renamed for clarity within AppContext
const ParsedConfig = std.json.Parsed(Config);
const ParsedStrat = std.json.Parsed(Strat);

pub const AppContext = struct {
    allocator: Allocator,
    config: ParsedConfig,
    strategy: ParsedStrat,
    ohlcvData: csv.Table,
    // Store the raw CSV data buffer pointer to manage its lifetime
    _csvDataBuffer: []u8,

    pub fn init(alloc: Allocator) !AppContext {
        var self: AppContext = undefined;
        self.allocator = alloc;

        // Load main config
        const configData = try std.fs.cwd().readFileAlloc(alloc, "config/config.json", 512);
        // Defer freeing configData *only* if parsing fails, otherwise free it after parsing.
        errdefer alloc.free(configData);
        self.config = try std.json.parseFromSlice(Config, alloc, configData, .{ .allocate = .alloc_always });
        // Free the original buffer now that parsing is successful and data is copied.
        alloc.free(configData);
        errdefer self.config.deinit(); // This handles freeing the *parsed* data on later errors.

        // Load strategy settings
        const strategyFileName = self.config.value.strategy;
        const strategyFilePath = try std.fmt.allocPrint(alloc, "config/{s}", .{strategyFileName});
        defer alloc.free(strategyFilePath); // Free the path string itself

        const stratData = try std.fs.cwd().readFileAlloc(alloc, strategyFilePath, 512);
        // Defer freeing stratData *only* if parsing fails.
        errdefer alloc.free(stratData);
        self.strategy = try std.json.parseFromSlice(Strat, alloc, stratData, .{ .allocate = .alloc_always });
        // Free the original buffer now that parsing is successful.
        alloc.free(stratData);
        errdefer self.strategy.deinit(); // Handles freeing *parsed* strategy data on later errors.

        // Load OHLCV data
        const dataFileName = self.config.value.data;
        const dataFilePath = try std.fmt.allocPrint(alloc, "data/{s}", .{dataFileName});
        defer alloc.free(dataFilePath); // Free the path string

        // Read CSV data but keep the buffer alive
        self._csvDataBuffer = try std.fs.cwd().readFileAlloc(alloc, dataFilePath, 1 * 1024 * 1024); // Max 1MB
        errdefer alloc.free(self._csvDataBuffer); // Free buffer if table parsing fails

        self.ohlcvData = csv.Table.init(alloc, csv.Settings.default());
        errdefer self.ohlcvData.deinit(); // Deinit table if parsing fails
        errdefer alloc.free(self._csvDataBuffer); // Also free buffer if table parsing fails AFTER init

        try self.ohlcvData.parse(self._csvDataBuffer);

        // Success path: Transfer ownership/responsibility to the AppContext instance
        return self;
    }

    pub fn deinit(self: *AppContext) void {
        self.ohlcvData.deinit();
        // Free the raw CSV data buffer we kept alive
        self.allocator.free(self._csvDataBuffer);
        self.strategy.deinit();
        self.config.deinit();
        // Note: We don't deinit the allocator itself here, assuming it's managed externally (e.g., GPA in main)
    }
};

test "loadConfig" {
    // Test the new AppContext init
    // Use the testing allocator directly for automatic leak detection
    const allocator = std.testing.allocator;

    // Mock file system (Assuming a test setup or adjust paths)
    // For simplicity, we'll assume config/config.json, config/buy-and-hold.json, data/btc.csv exist
    // In a real scenario, you'd mock std.fs.cwd() or create temporary test files.

    // Create dummy files for testing if they don't exist
    _ = std.fs.cwd().makePath("config") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };
    _ = std.fs.cwd().makePath("data") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };

    var config_file = try std.fs.cwd().createFile("config/config.json", .{});
    defer config_file.close();
    _ = try config_file.writeAll(
        \\{
        \\  "budget": 10000,
        \\  "strategy": "buy-and-hold.json",
        \\  "data": "btc.csv"
        \\}
    );

    var strat_file = try std.fs.cwd().createFile("config/buy-and-hold.json", .{});
    defer strat_file.close();
    _ = try strat_file.writeAll(
        \\{
        \\  "buyAt": 1000
        \\}
    );

    var data_file = try std.fs.cwd().createFile("data/btc.csv", .{});
    defer data_file.close();
    _ = try data_file.writeAll(
        \\timestamp,open,high,low,close,volume
        \\2024-01-01T00:00:00Z,42000.00,42100.00,41900.00,42050.00,100.50
    );

    var context = try AppContext.init(allocator);
    defer context.deinit();

    try std.testing.expectEqual(@as(u64, 10000), context.config.value.budget);
    try std.testing.expectEqualSlices(u8, "buy-and-hold.json", context.config.value.strategy);
    try std.testing.expectEqualSlices(u8, "btc.csv", context.config.value.data);
    try std.testing.expectEqual(@as(u64, 1000), context.strategy.value.buyAt);
    try std.testing.expectEqual(@as(usize, 1), context.ohlcvData.body.items.len); // Check if CSV data was loaded

    // Clean up dummy files
    try std.fs.cwd().deleteFile("config/config.json");
    try std.fs.cwd().deleteFile("config/buy-and-hold.json");
    try std.fs.cwd().deleteFile("data/btc.csv");
    try std.fs.cwd().deleteDir("config");
    try std.fs.cwd().deleteDir("data");
}

// Comment out old tests or remove them
// test "loadConfig" {
//     const config = try loadConfig(std.testing.allocator);
//     defer config.deinit();
//
//     try std.testing.expectEqual(@as(u64, 10000), config.value.budget);
//     try std.testing.expectEqualSlices(u8, "buy-and-hold.json", config.value.strategy);
//     try std.testing.expectEqualSlices(u8, "btc.csv", config.value.data);
// }
//
// test "loadStrategySettings" {
//     // Need to create dummy config/buy-and-hold.json for this test
//     // ... (test setup code) ...
//     const strat = try loadStrategySettings(std.testing.allocator, "config/buy-and-hold.json");
//     defer strat.deinit();
//
//     try std.testing.expectEqual(@as(u64, 1000), strat.value.buyAt);
//     // ... (test cleanup code) ...
// }
