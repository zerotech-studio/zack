const std = @import("std");
const common = @import("common.zig");
const Bar = common.Bar;
const Signal = common.Signal;
const StratConfig = @import("../utils/load-config.zig").Strat; // Strategy settings from config

pub const BuyAndHoldStrategy = struct {
    config: StratConfig, // Store the strategy-specific settings

    pub fn init(strategy_config: StratConfig) BuyAndHoldStrategy {
        return BuyAndHoldStrategy{
            .config = strategy_config,
        };
    }

    // Generates a signal based on the current bar and whether a position is already held.
    // Returns null if no signal should be generated for this bar.
    pub fn generateSignal(self: BuyAndHoldStrategy, bar: Bar, has_position: bool) ?Signal {
        // Buy condition: Open price hits the threshold AND we are not already in a position.
        if (!has_position and bar.open >= @as(f64, @floatFromInt(self.config.buyAt))) {
            // Buy signal
            return Signal{ .type = .Long };
        } else {
            // No action needed (either already holding or price condition not met)
            return null;
        }

        // Note: A pure "Buy and Hold" doesn't typically have an exit signal based on price.
        // Exiting would usually happen at the end of the backtest period.
        // We could add an 'Exit' signal later if needed for other strategy types.
    }

    pub fn deinit(self: *BuyAndHoldStrategy) void {
        // No allocations were made specific to this struct currently
        _ = self;
    }
};

// TODO: Add test cases for BuyAndHoldStrategy
