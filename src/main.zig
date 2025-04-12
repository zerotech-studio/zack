const std = @import("std");
const Allocator = std.mem.Allocator;

const loadConfig = @import("utils/load-config.zig").loadConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const parsed = try loadConfig(allocator);
    defer parsed.deinit();

    const config = parsed.value;

    const budget = config.budget;

    std.debug.print("budget: {d}\nstring: {s}", .{ budget, config.testy });
}
