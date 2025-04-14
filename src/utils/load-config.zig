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
