# 📈 Zack: A Simple Backtesting Engine in Zig 📉

Welcome to Zack! This project is a lightweight yet powerful backtesting engine for trading strategies, written entirely in Zig ⚡. It allows you to test your trading ideas against historical market data to see how they might have performed.

## 🤔 What is it?

Zack simulates the process of trading based on a predefined strategy using historical OHLCV (Open, High, Low, Close, Volume) data. It processes data bar-by-bar, generates trading signals, simulates order execution, manages a virtual portfolio, and reports the performance.

## ✨ Why Zig?

Zig offers several advantages for this kind of application:

*   **Performance:** Zig compiles to fast, efficient machine code, crucial for processing potentially large datasets quickly.
*   **Memory Control:** Manual memory management allows for fine-tuned optimization and avoids hidden overhead.
*   **Simplicity:** Zig's focus on simplicity and explicitness makes the codebase easier to understand and maintain (no hidden control flow!).
*   **Safety:** While offering low-level control, Zig includes features to help catch bugs at compile time.

## ⚙️ How it Works: The Engine Flow

The backtesting process is driven by an event loop within the `BacktestEngine`. Here's a breakdown of the core components and their interactions:

1.  **Initialization:**
    *   The `main` function loads configuration (`config/config.json`, `config/<strategy_name>.json`) and CSV data (`data/<data_file>.csv`) using `AppContext`.
    *   It then initializes the `BacktestEngine`, which in turn sets up all other components.

2.  **The Event Loop (`BacktestEngine.run`):**
    The engine iterates through the historical data bar by bar. For each `current_bar`:

    *   **Data Handling (`DataHandler`):** Provides the `current_bar` (parsed from the CSV data). It uses `Bar.parse` to convert CSV rows into structured `Bar` objects.
    *   **Portfolio Update (`Portfolio`):** The portfolio calculates its current market value based on the `current_bar.close` price and any open `Position`. It records the total equity at this point in time (`EquityPoint`).
    *   **Lookahead:** The engine fetches the `next_bar` from the `DataHandler`. This is crucial for simulating execution delays.
    *   **Strategy Signal (`BuyAndHoldStrategy`):** The current strategy (`BuyAndHoldStrategy` in this case) receives the `current_bar` data and the portfolio's state (e.g., `has_position`). It decides if a trading signal (`Signal`) should be generated based on its rules (e.g., `bar.open >= buyAt`).
        ```zig
        // Inside strategy.generateSignal
        if (!has_position and bar.open >= @as(f64, @floatFromInt(self.config.buyAt))) {
            return Signal{ .type = .Long }; // Generate Buy signal
        }
        ```
    *   **Order Generation (`Portfolio`):** If a `Signal` is received, the `Portfolio` determines the details of the `Order` (e.g., `MarketBuy`, quantity). It might use the `current_bar`'s price for approximate sizing.
        ```zig
        // Inside portfolio.handleSignal
        const quantity_to_buy = cash_to_use / current_bar.close;
        return Order{ .type = .MarketBuy, .quantity = quantity_to_buy };
        ```
    *   **Execution Simulation (`ExecutionHandler`):** The `Order` is sent to the `ExecutionHandler`. **Crucially**, it uses the `next_bar.open` price to simulate the fill, modeling the delay between deciding to trade and the order actually executing in the next period. It also calculates commission.
        ```zig
        // Inside execution_handler.executeOrder
        const fill_price = next_bar.open; // Fill at NEXT bar's open
        const commission = COMMISSION_PER_TRADE;
        return Fill{ /* ...details... */ };
        ```
    *   **Portfolio Update (`Portfolio`):** The resulting `Fill` event is sent back to the `Portfolio`, which updates its `current_cash`, `position`, and `current_holdings_value`.
        ```zig
        // Inside portfolio.handleFill
        self.current_cash -= cost;
        self.position = Position{ .entry_price = fill.fill_price, /*...*/ };
        ```
    *   **Loop:** The process repeats with the `next_bar` becoming the `current_bar`.

3.  **Results:** After processing all bars, the `BacktestEngine.logResults` function prints a summary of the performance.

## 🎯 Current Strategy: Buy and Hold

The engine currently implements a simple "Buy and Hold" strategy (`src/engine/strategy.zig`).

*   **Logic:** It generates a single "Buy" (`Long`) signal when the `open` price of a bar crosses above a predefined threshold (`buyAt`), but *only if* the portfolio does not already hold a position. It never generates a sell signal; the position is held until the end of the backtest.
*   **Configuration:** The `buyAt` threshold is set in the strategy's configuration file (e.g., `config/buy-and-hold.json`):
    ```json
    {
      "buyAt": 1000
    }
    ```

## 🛠️ Configuration

The main simulation parameters are set in `config/config.json`:

```json
{
  "budget": 10000,         // Initial capital for the simulation
  "strategy": "buy-and-hold.json", // Which strategy config file to load from config/
  "data": "btc.csv"        // Which data file to load from data/
}
```

## 📊 Data Format

The engine expects OHLCV data in CSV format in the `data/` directory:

```csv
timestamp,open,high,low,close,volume
2024-01-01T00:00:00Z,42000.00,42100.00,41900.00,42050.00,100.50
2024-01-01T01:00:00Z,42050.00,42200.00,42000.00,42150.00,120.75
...
```

*   `timestamp`: ISO 8601 format (currently treated as a string).
*   `open`, `high`, `low`, `close`, `volume`: Floating-point numbers.

## 📁 Project Structure

```
.
├── build.zig        # Zig build script
├── config/
│   ├── config.json         # Main configuration
│   └── buy-and-hold.json   # Strategy-specific parameters
├── data/
│   └── btc.csv             # Sample OHLCV data
├── src/
│   ├── main.zig            # Application entry point
│   ├── csv/                # CSV parser utility
│   │   └── csv-parser.zig
│   ├── engine/             # Core backtesting engine components
│   │   ├── common.zig          # Shared structs (Bar, Signal, Order, Fill, Position)
│   │   ├── data_handler.zig    # Loads and provides Bars
│   │   ├── strategy.zig        # Strategy logic (BuyAndHoldStrategy)
│   │   ├── portfolio.zig       # Manages cash, position, equity
│   │   ├── execution_handler.zig # Simulates order fills
│   │   └── backtest_engine.zig # Orchestrates the simulation loop
│   └── utils/              # Utility functions
│       ├── load-config.zig   # JSON config loading
│       └── logger.zig        # Simple logging utility
└── README.md       # This file
```

## 🚀 How to Run

1.  Ensure you have Zig installed (see [ziglang.org](https://ziglang.org/learn/getting-started/)).
2.  Clone the repository.
3.  Run the simulation using the Zig build system:

    ```bash
    zig build run
    ```
    Alternatively, run the main file directly:
    ```bash
    zig run src/main.zig
    ```

## 📝 Example Output

Running the engine with the default configuration and sample `btc.csv` data produces output similar to this:

```
ℹ️ [INFO] ⚙️ Configuration Loaded:
ℹ️ [INFO]   Budget:   10000
ℹ️ [INFO]   Strategy: buy-and-hold.json
ℹ️ [INFO]   Data File:btc.csv
ℹ️ [INFO] 📈 Strategy Settings:
ℹ️ [INFO]   Buy At Threshold: 1000

--- Starting Backtest Run ---
PORTFOLIO: Received LONG signal, generating MarketBuy order for ~0.23547619047619048 units.
EXECUTION: Executing MarketBuy order for 0.23547619047619048 units @ 42050 (Commission: 1)
PORTFOLIO: Handled MarketBuy fill. Cash: 9.99999999999909, Position Qty: 0.23547619047619048, Entry: 42050
--- Backtest Run Finished ---

ℹ️ [INFO]
📊 Backtest Results:
ℹ️ [INFO]   Initial Capital: 10000.00
ℹ️ [INFO]   Final Equity:    10443.75
ℹ️ [INFO]   Total Return:    4.44%
ℹ️ [INFO]   Ending Position: 0.2355 units @ entry 42050.00
ℹ️ [INFO]   (More detailed performance metrics TBD)

Application finished successfully.

```
*(Note: Exact float values might differ slightly)*

**Key Observations from Output:**

*   The `Long` signal is generated based on the *first* bar (`open`=42000 >= `buyAt`=1000).
*   The `MarketBuy` order is executed at the `open` price of the *second* bar (42050), as expected due to the one-bar delay simulation.
*   The final equity reflects the initial capital minus the buy cost plus the value of the holding at the final bar's close price.

## 🔮 Future Work

*   Implement more sophisticated performance metrics (Sharpe Ratio, Max Drawdown, etc.).
*   Implement more strategies.
*   Implement technical indicators.
*   Add comprehensive unit tests for all engine components.

Contributions and suggestions are welcome!