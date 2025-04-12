const std = @import("std");
const Allocator = std.mem.Allocator;

// This struct should always match the config.json file
const Config = struct {
    budget: u64,
    strategy: []const u8,
    data: []const u8,
};

pub fn loadConfig(alloc: Allocator) !std.json.Parsed(Config) {
    const data = try std.fs.cwd().readFileAlloc(alloc, "config/config.json", 512);
    defer alloc.free(data);

    return std.json.parseFromSlice(Config, alloc, data, .{ .allocate = .alloc_always });
}

test "loadConfig" {
    const config = try loadConfig(std.testing.allocator);
    defer config.deinit();

    try std.testing.expectEqual(@as(u64, 10000), config.value.budget);
    try std.testing.expectEqualSlices(u8, "buy-and-hold.json", config.value.strategy);
    try std.testing.expectEqualSlices(u8, "btc.csv", config.value.data);
}
