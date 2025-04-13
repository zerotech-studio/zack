const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const Bar = common.Bar;
const Signal = common.Signal;
const Order = common.Order;
const Fill = common.Fill;
const Position = common.Position;

const EquityPoint = struct {
    timestamp_str: []const u8,
    total_equity: f64,
};

pub const Portfolio = struct {
    allocator: Allocator,
    initial_capital: f64,
    current_cash: f64,
    current_holdings_value: f64,
    current_total_equity: f64,
    position: ?Position, // Single position for now
    equity_curve: std.ArrayList(EquityPoint),

    pub fn init(alloc: Allocator, initial_capital_u64: u64) !Portfolio {
        const initial_capital_f64 = @as(f64, @floatFromInt(initial_capital_u64));
        return Portfolio{
            .allocator = alloc,
            .initial_capital = initial_capital_f64,
            .current_cash = initial_capital_f64,
            .current_holdings_value = 0.0,
            .current_total_equity = initial_capital_f64,
            .position = null,
            .equity_curve = std.ArrayList(EquityPoint).init(alloc),
        };
    }

    pub fn deinit(self: *Portfolio) void {
        // Free the equity curve points (assuming timestamps were allocated if needed)
        // If timestamp_str just references Bar data, no extra free needed here.
        self.equity_curve.deinit();
        // The allocator itself is managed externally
    }

    // Updates holdings value based on the current bar's price and records equity.
    pub fn updateMarketValueAndRecordEquity(self: *Portfolio, current_bar: Bar) !void {
        if (self.position) |pos| {
            self.current_holdings_value = pos.getMarketValue(current_bar.close);
        } else {
            self.current_holdings_value = 0.0;
        }
        self.current_total_equity = self.current_cash + self.current_holdings_value;

        // Record equity point
        // TODO: Decide if we need to allocate/copy the timestamp string
        // For now, assume it's safe to reference the bar's string
        const point = EquityPoint{
            .timestamp_str = current_bar.timestamp_str,
            .total_equity = self.current_total_equity,
        };
        try self.equity_curve.append(point);
    }

    // Processes a signal from the strategy and generates an order if appropriate.
    // For Buy & Hold, we buy with (almost) all cash on the first Long signal.
    pub fn handleSignal(self: *Portfolio, signal: Signal, current_bar: Bar) ?Order {
        // _ = current_bar; // Price info not strictly needed for market order sizing here -- REMOVED

        switch (signal.type) {
            .Long => {
                // Only act if we don't already have a position
                if (self.position == null) {
                    // Simple sizing: use 99% of cash to leave buffer for commission
                    // More sophisticated sizing would use risk % or fixed fractional.
                    const cash_to_use = self.current_cash * 0.99;
                    // Rough quantity estimate based on current close - execution handler will use actual fill price.
                    // Avoid division by zero if price is somehow zero.
                    if (current_bar.close <= 0) return null;
                    const quantity_to_buy = cash_to_use / current_bar.close;

                    if (quantity_to_buy > 0) {
                        std.debug.print("PORTFOLIO: Received LONG signal, generating MarketBuy order for ~{d} units.\n", .{quantity_to_buy});
                        return Order{ .type = .MarketBuy, .quantity = quantity_to_buy };
                    } else {
                        std.debug.print("PORTFOLIO: Received LONG signal, but not enough cash ({d}) to buy at price {d}.\n", .{ self.current_cash, current_bar.close });
                        return null;
                    }
                } else {
                    // Already have a position, ignore Long signal for Buy & Hold
                    return null;
                }
            },
            .Exit => {
                // Exit signal (not used by simple Buy & Hold, but handle if received)
                if (self.position) |pos| {
                    std.debug.print("PORTFOLIO: Received EXIT signal, generating MarketSell order for {d} units.\n", .{pos.quantity});
                    return Order{ .type = .MarketSell, .quantity = pos.quantity };
                } else {
                    // No position to exit
                    return null;
                }
            },
        }
    }

    // Updates portfolio state based on a confirmed fill event.
    pub fn handleFill(self: *Portfolio, fill: Fill) void {
        switch (fill.order_type) {
            .MarketBuy => {
                const cost = (fill.quantity * fill.fill_price) + fill.commission;
                self.current_cash -= cost;
                // Update or create position
                // Simple case: Assume full fill replaces any prior position (shouldn't happen in B&H)
                self.position = Position{
                    .entry_price = fill.fill_price,
                    .quantity = fill.quantity,
                };
                self.current_holdings_value = fill.quantity * fill.fill_price; // Initial value at fill
                std.debug.print("PORTFOLIO: Handled MarketBuy fill. Cash: {d}, Position Qty: {d}, Entry: {d}\n", .{ self.current_cash, self.position.?.quantity, self.position.?.entry_price });
            },
            .MarketSell => {
                if (self.position == null) {
                    // This shouldn't happen if logic is correct
                    std.debug.print("WARN: Received MarketSell fill but have no position!\n", .{});
                    return;
                }
                // Ensure selling quantity doesn't exceed holdings (simple check)
                const sell_quantity = @min(fill.quantity, self.position.?.quantity);
                const proceeds = (sell_quantity * fill.fill_price) - fill.commission;
                self.current_cash += proceeds;

                const remaining_quantity = self.position.?.quantity - sell_quantity;
                if (remaining_quantity <= 1e-9) { // Check for effectively zero quantity due to float math
                    self.position = null;
                    self.current_holdings_value = 0.0;
                    std.debug.print("PORTFOLIO: Handled MarketSell fill (closed position). Cash: {d}\n", .{self.current_cash});
                } else {
                    // Partial sell (shouldn't happen with current B&H logic)
                    self.position.?.quantity = remaining_quantity;
                    self.current_holdings_value = remaining_quantity * fill.fill_price; // Value at fill price
                    std.debug.print("PORTFOLIO: Handled MarketSell fill (partial). Cash: {d}, Remaining Qty: {d}\n", .{ self.current_cash, self.position.?.quantity });
                }
            },
        }
        // Recalculate total equity after cash/holdings change
        self.current_total_equity = self.current_cash + self.current_holdings_value;
    }
};

// TODO: Add test cases for Portfolio
