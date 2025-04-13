const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const Bar = common.Bar;
const DataHandler = @import("data_handler.zig").DataHandler;
const BuyAndHoldStrategy = @import("strategy.zig").BuyAndHoldStrategy;
const Portfolio = @import("portfolio.zig").Portfolio;
const ExecutionHandler = @import("execution_handler.zig").ExecutionHandler;
const AppContext = @import("../utils/load-config.zig").AppContext;
const logger = @import("../utils/logger.zig"); // For results logging

pub const BacktestEngine = struct {
    allocator: Allocator,
    data_handler: DataHandler,
    strategy: BuyAndHoldStrategy,
    portfolio: Portfolio,
    execution_handler: ExecutionHandler,

    pub fn init(alloc: Allocator, context: *AppContext) !BacktestEngine {
        return BacktestEngine{
            .allocator = alloc,
            .data_handler = DataHandler.init(alloc, context.ohlcvData.body), // Pass CSV rows
            .strategy = BuyAndHoldStrategy.init(context.strategy.value), // Pass strategy config
            .portfolio = try Portfolio.init(alloc, context.config.value.budget), // Pass initial budget
            .execution_handler = ExecutionHandler{}, // Stateless for now
        };
    }

    pub fn deinit(self: *BacktestEngine) void {
        // Deinitialize components that hold allocated resources
        self.portfolio.deinit();
        self.strategy.deinit();
        // DataHandler doesn't own the rows, AppContext does.
        // Allocator is managed externally.
    }

    pub fn run(self: *BacktestEngine) !void {
        std.debug.print("\n--- Starting Backtest Run ---\n", .{});
        var current_bar: ?Bar = null;
        var next_bar: ?Bar = null;

        // Prime the pump: get the first bar
        next_bar = self.data_handler.nextBar() catch |err| {
            std.debug.print("ERROR: Failed to get first bar: {s}\n", .{@errorName(err)});
            return err;
        };

        while (next_bar) |nb| {
            // Shift bars: the 'next_bar' becomes the 'current_bar'
            current_bar = nb;
            const current_bar_val = current_bar.?;

            // 1. Update Portfolio mark-to-market value based on the *current* bar's close
            //    and record equity for this timestamp.
            try self.portfolio.updateMarketValueAndRecordEquity(current_bar_val);

            // --- Look ahead to the *next* bar for execution ---
            // Important for simulating execution delay
            next_bar = self.data_handler.nextBar() catch |err| {
                std.debug.print("ERROR: Failed to get next bar: {s}\n", .{@errorName(err)});
                // Decide how to handle errors: stop backtest? skip bar?
                return err;
            };

            // --- Event Processing using *current* bar data ---

            // 2. Pass *current* bar data to Strategy -> receive Signal(s)
            const maybe_signal = self.strategy.generateSignal(current_bar_val, self.portfolio.position != null);

            var maybe_order: ?common.Order = null;
            if (maybe_signal) |signal| {
                // 3. Pass Signal(s) to Portfolio -> receive Order(s)
                //    Portfolio uses current_bar data for rough sizing if needed.
                maybe_order = self.portfolio.handleSignal(signal, current_bar_val);
            }

            // 4. Pass Order(s) to Execution Handler -> receive Fill(s)
            //    Execution uses *next* bar's data (e.g., open price) for fill simulation.
            if (maybe_order) |order| {
                if (next_bar) |actual_next_bar| {
                    const maybe_fill = self.execution_handler.executeOrder(order, actual_next_bar);

                    if (maybe_fill) |fill| {
                        // 5. Pass Fill(s) back to Portfolio to update holdings/cash
                        self.portfolio.handleFill(fill);
                    }
                } else {
                    // Order generated on the last bar, cannot execute as there's no next bar.
                    std.debug.print("ENGINE: Order generated on last bar, cannot execute.\n", .{});
                }
            }

            // 6. Record state/metrics (done partially by portfolio equity update)

            // Loop continues: next_bar becomes current_bar in the next iteration
        }

        std.debug.print("--- Backtest Run Finished ---\n", .{});

        // 7. Final Performance Calculation (after loop)
        self.logResults();
    }

    fn logResults(self: *BacktestEngine) void {
        logger.log(.Info, "\n📊 Backtest Results:", .{});
        logger.log(.Info, "  Initial Capital: {d}", .{self.portfolio.initial_capital});
        logger.log(.Info, "  Final Equity:    {d}", .{self.portfolio.current_total_equity});

        const total_return_pct = if (self.portfolio.initial_capital > 0) (self.portfolio.current_total_equity / self.portfolio.initial_capital - 1.0) * 100.0 else 0.0;
        logger.log(.Info, "  Total Return:    {d}%", .{total_return_pct});

        if (self.portfolio.position) |pos| {
            logger.log(.Info, "  Ending Position: {d} units @ entry {d}", .{ pos.quantity, pos.entry_price });
        } else {
            logger.log(.Info, "  Ending Position: None", .{});
        }

        // TODO: Calculate more metrics (Sharpe, Drawdown, etc.) using self.portfolio.equity_curve
        logger.log(.Info, "  (More detailed performance metrics TBD)", .{});
    }
};
