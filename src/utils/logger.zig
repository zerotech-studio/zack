const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const fmt = std.fmt;
const fs = std.fs;
const time = std.time;
const csv = @import("csv/csv-parser.zig"); // For Table type if needed, maybe not directly
const Config = @import("load-config.zig").Config;
const Strat = @import("load-config.zig").Strat;

// Basic Log Level Enum (can be expanded later)
const LogLevel = enum { Info, Warn, Error, Debug };

// Simple log function with timestamp and level (optional)
pub fn log(level: LogLevel, comptime format: []const u8, args: anytype) void {
    // In the future, we could add timestamps, write to files, etc.
    const level_str = switch (level) {
        .Info => "INFO",
        .Warn => "WARN",
        .Error => "ERR ", // Extra space for alignment
        .Debug => "DBUG",
    };
    const prefix = switch (level) {
        .Info => "ℹ️ ",
        .Warn => "⚠️ ",
        .Error => "❌ ",
        .Debug => "🐛 ",
    };

    // Basic console output for now
    print("{s}[{s}] ", .{ prefix, level_str });
    print(format, args);
    print("\n", .{});
}

// --- Specific Log Functions ---

pub fn logConfig(config: Config) void {
    log(.Info, "⚙️ Configuration Loaded:", .{});
    log(.Info, "  Budget:   ${d}", .{config.budget});
    log(.Info, "  Strategy: {s}", .{config.strategy});
    log(.Info, "  Data File:{s}", .{config.data});
}

pub fn logStrategy(strat: Strat) void {
    log(.Info, "📈 Strategy Settings:", .{});
    // Example: Assuming 'buyAt' means something specific, adjust as needed
    log(.Info, "  Buy At Threshold: {d}", .{strat.buyAt});
}

pub fn logOhlcvHeader() void {
    // Use fixed-width formatting later if needed
    log(.Info, "📊 OHLCV Data Preview (first 10 rows):", .{});
    log(.Info, "  {s:<25} | {s:>10} | {s:>10} | {s:>10} | {s:>10} | {s:>12}", .{
        "Timestamp", "Open", "High", "Low", "Close", "Volume",
    });
    log(.Info, "  {s}", .{"-" ** 80}); // Separator
}

// Helper to parse a CSV row string for pretty printing
// Returns an optional struct containing parsed values. Returns null on parsing error.
const OhlcvRowData = struct {
    timestamp: []const u8,
    open: f64,
    high: f64,
    low: f64,
    close: f64,
    volume: f64,

    fn parse(row_str: []const u8, allocator: Allocator) !?OhlcvRowData {
        _ = std.io.fixedBufferStream(row_str); // Keep stream for potential future use, but ignore reader
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();

        // Simple split by comma - assumes no escaped commas within fields
        var tokenizer = std.mem.tokenizeAny(u8, row_str, ",");
        while (tokenizer.next()) |part| {
            try parts.append(part);
        }

        if (parts.items.len != 6) {
            log(.Warn, "⚠️ Could not parse OHLCV row for logging (expected 6 fields, got {d}): {s}", .{ parts.items.len, row_str });
            return null; // Indicate parsing failure
        }

        var self: OhlcvRowData = undefined;
        self.timestamp = parts.items[0]; // Keep as string
        self.open = try fmt.parseFloat(f64, parts.items[1]);
        self.high = try fmt.parseFloat(f64, parts.items[2]);
        self.low = try fmt.parseFloat(f64, parts.items[3]);
        self.close = try fmt.parseFloat(f64, parts.items[4]);
        self.volume = try fmt.parseFloat(f64, parts.items[5]);

        return self;
    }
};

pub fn logOhlcvRowPretty(row_str: []const u8, allocator: Allocator) void {
    var temp_allocator = std.heap.ArenaAllocator.init(allocator);
    defer temp_allocator.deinit();
    const arena = temp_allocator.allocator();

    const maybe_parsed_row = OhlcvRowData.parse(row_str, arena) catch |err| {
        log(.Warn, "⚠️ Error parsing OHLCV row for logging: {s}", .{@errorName(err)});
        log(.Warn, "   Raw row: {s}", .{row_str});
        return; // Don't log if parsing fundamentally failed (e.g., allocation)
    };

    if (maybe_parsed_row) |row_data| {
        // Basic formatting, adjust widths as needed
        log(.Info, "  {s:<25} | {d:>10.2} | {d:>10.2} | {d:>10.2} | {d:>10.2} | {d:>12.2}", .{
            row_data.timestamp, row_data.open, row_data.high, row_data.low, row_data.close, row_data.volume,
        });
    } else {
        // Log the raw string if parsing failed (e.g., wrong number of fields)
        // The warning about parsing failure was already logged inside OhlcvRowData.parse
        // log(.Info, "  Raw: {s}", .{row_str}); // Optionally log raw string on parse fail
    }
}

// Example: Future function placeholder
pub fn logTrade() void {
    log(.Info, "📈 Trade Executed: [Details]", .{});
}
