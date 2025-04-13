const std = @import("std");
const common = @import("common.zig");
const Bar = common.Bar;
const Order = common.Order;
const Fill = common.Fill;

// Simple fixed commission per trade for now
const COMMISSION_PER_TRADE = 1.0; // Example: $1 per trade

// Simulates the execution of orders.
// For simplicity, assumes market orders fill at the open price of the *next* bar.
// This introduces a one-bar delay, which is common in simple bar-based backtests.
pub const ExecutionHandler = struct {

    // Takes an order and the bar *following* the one that generated the order signal.
    // Returns a Fill event if the order can be executed.
    pub fn executeOrder(self: ExecutionHandler, order: Order, next_bar: Bar) ?Fill {
        _ = self; // Not stateful for now

        // Simple model: Market orders fill at the open of the next bar.
        // We ignore potential slippage for now.
        const fill_price = next_bar.open;

        // Basic validation: ensure positive fill price and quantity
        if (fill_price <= 0 or order.quantity <= 0) {
            std.debug.print("EXECUTION: Order rejected. Invalid price ({d}) or quantity ({d}).\n", .{ fill_price, order.quantity });
            return null;
        }

        const commission = COMMISSION_PER_TRADE;

        std.debug.print("EXECUTION: Executing {s} order for {d} units @ {d} (Commission: {d})\n", .{
            @tagName(order.type),
            order.quantity,
            fill_price,
            commission,
        });

        return Fill{
            .timestamp_str = next_bar.timestamp_str, // Fill happens on this bar's open
            .order_type = order.type,
            .quantity = order.quantity, // Assume full fill for now
            .fill_price = fill_price,
            .commission = commission,
        };
    }
};

// TODO: Add test cases for ExecutionHandler (e.g., handling zero price)
