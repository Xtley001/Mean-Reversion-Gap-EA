# Multi-Symbol Trading EA Documentation

## Overview

This Expert Advisor (EA) is a sophisticated multi-symbol, multi-timeframe trading system designed for prop firm trading environments. It implements a comprehensive risk management system with fixed dollar risk per trade, dynamic trailing stops, and multiple safety features to protect against drawdowns.

## Key Features

### 🎯 Core Trading Strategy
- **Multi-MA Gap Strategy**: Uses two moving averages (360 & 20 periods) with gap-based entry conditions
- **ATR-Based Volatility Filter**: Trades only when fast ATR < slow ATR (low volatility periods)
- **RSI Momentum Confirmation**: Additional filter using RSI divergence patterns
- **Limit Order Execution**: Places limit orders at optimal entry points instead of market orders

### 🛡️ Advanced Risk Management
- **Fixed Dollar Risk**: Each trade risks exactly $50 (configurable)
- **5:1 Risk-Reward Ratio**: Targets $250 profit for every $50 risk
- **Dynamic Position Sizing**: Automatically calculates lot sizes based on stop loss distance
- **Trailing Stop System**: Moves stop loss to breakeven and beyond in $50 profit increments
- **Daily Loss Limits**: Automatic shutdown at daily loss threshold
- **Maximum Drawdown Protection**: Stops trading when account drawdown exceeds limit

### 📊 Multi-Asset Trading
- **12 Trading Instruments**: Gold, Bitcoin, US30, major forex pairs, Ethereum, Oil, Silver
- **3 Timeframes**: M5, M15, M30 for multiple entry opportunities
- **Symbol-Specific Settings**: Customized parameters for each asset class

### ⏰ Session Management
- **Lagos Time Trading Hours**: Optimized for GMT+1 timezone
- **Automatic Session Detection**: Sunday 22:15 to Friday 21:45 Lagos time
- **Weekend Protection**: No trading during market closure

### 📈 Prop Firm Compliance
- **Daily Profit Targets**: Configurable daily profit goals
- **Maximum Loss Limits**: Daily and overall drawdown protection
- **Trade Journaling**: Comprehensive CSV logging of all trades
- **Spread Filtering**: Avoids trading during high spread conditions

## Supported Symbols

The EA trades the following symbols (with 'z' suffix):
- **Metals**: XAUUSDz (Gold), XAGUSDz (Silver)
- **Crypto**: BTCUSDz (Bitcoin), ETHUSDz (Ethereum)
- **Indices**: US30z (Dow Jones)
- **Forex**: USDJPYz, GBPJPYz, EURGBPz, AUDJPYz, EURUSDz, GBPUSDz
- **Commodities**: USOILz (Crude Oil)

## Configuration Parameters

### Risk Management Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `RiskPerTrade` | 50 | Fixed dollar amount to risk per trade |
| `RiskRewardRatio` | 5 | Target reward relative to risk (5:1 = $250 profit for $50 risk) |
| `StopLossATRFactor` | 1.5 | ATR multiplier for stop loss calculation |
| `TrailingStopATRFactor` | 1.0 | ATR multiplier for trailing stop |
| `OrderExpirationBars` | 5 | Number of bars before limit orders expire |
| `MinLotSize` | 0.01 | Minimum position size |
| `MaxLotSize` | 1.0 | Maximum position size |

### Strategy Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MinMaGap` | 0.6 | Minimum MA gap percentage for trade entry |
| `Ma1Period` | 360 | Fast moving average period |
| `Ma2Period` | 20 | Slow moving average period |
| `Atr1Period` | 10 | Fast ATR period |
| `Atr2Period` | 20 | Slow ATR period |
| `RsiPeriod` | 20 | RSI calculation period |

### Trading Controls

| Parameter | Default | Description |
|-----------|---------|-------------|
| `EnableBuy` | true | Allow long positions |
| `EnableSell` | true | Allow short positions |
| `MaxTradesPerSymbolTF` | 1 | Maximum trades per symbol/timeframe |
| `MaxGlobalTrades` | 15 | Maximum simultaneous positions |
| `MinBarsBetweenTrades` | 5 | Minimum bars between trades on same symbol |
| `LimitOrderDistance` | 2.0 | Pips distance from market for limit orders |

### Session Settings (Lagos Time GMT+1)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `EnableSession` | true | Enable trading session filtering |
| `SundayOpen` | 22 | Sunday opening hour |
| `SundayOpenMin` | 15 | Sunday opening minute |
| `DailyClose` | 21 | Daily closing hour |
| `DailyCloseMin` | 45 | Daily closing minute |

### Prop Firm Protection

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DailyMaxLoss` | 500 | Maximum daily loss in dollars |
| `DailyProfitTarget` | 1000 | Daily profit target in dollars |
| `MaxDrawdownPercent` | 5.0 | Maximum account drawdown percentage |
| `MaxSpreadMultiplier` | 3.0 | Maximum spread multiplier vs average |

### Trade Journaling

| Parameter | Default | Description |
|-----------|---------|-------------|
| `EnableTradeJournal` | true | Enable trade logging |
| `JournalFileName` | "TradeJournal.csv" | Journal file name |

## Installation & Setup

### 1. MetaTrader Setup
1. Copy the EA file to your MetaTrader's `Experts` folder
2. Restart MetaTrader 5
3. Ensure all required symbols are available in Market Watch
4. Enable automated trading and allow DLL imports

### 2. Chart Configuration
- The EA can be attached to any chart
- It will automatically trade all configured symbols and timeframes
- Recommended: Attach to a 1-minute chart for optimal performance

### 3. Parameter Configuration
- Start with default parameters for initial testing
- Adjust risk parameters based on your account size and risk tolerance
- Enable session filtering if trading from different time zones

## Usage Guidelines

### For Beginners

**Conservative Settings:**
```
RiskPerTrade = 25          // Lower risk per trade
MaxGlobalTrades = 5        // Fewer simultaneous trades
DailyMaxLoss = 250         // Lower daily loss limit
RiskRewardRatio = 3        // More conservative R:R
```

### For Experienced Traders

**Aggressive Settings:**
```
RiskPerTrade = 100         // Higher risk per trade
MaxGlobalTrades = 20       // More simultaneous trades
DailyMaxLoss = 1000        // Higher daily loss limit
RiskRewardRatio = 5        // Higher reward target
```

### Asset-Specific Recommendations

**Forex Pairs (Major):**
- Use default ATR settings
- Consider lower MinMaGap (0.4-0.6)
- Monitor during high-impact news

**Gold/Silver:**
- Increase StopLossATRFactor to 2.0
- Use higher TrailingStopATRFactor (1.5)
- Be cautious during volatile sessions

**Crypto (BTC/ETH):**
- Monitor weekend gaps
- Consider wider stop losses
- Use smaller position sizes

**Indices (US30):**
- Increase MinMaGap to 0.8
- Monitor during market open/close
- Consider session-specific trading

## Risk Management Features

### 1. Fixed Dollar Risk
- Each trade risks exactly the specified dollar amount
- Position size automatically calculated based on stop loss distance
- Ensures consistent risk regardless of market conditions

### 2. Trailing Stop System
- Moves stop loss to breakeven after first $50 profit
- Continues trailing in $50 increments
- Maintains 5:1 risk-reward ratio throughout

### 3. Daily Limits
- Automatically stops trading when daily loss limit reached
- Optionally stops when daily profit target achieved
- Resets at start of new trading session

### 4. Drawdown Protection
- Monitors maximum account drawdown
- Stops trading when drawdown exceeds threshold
- Protects against catastrophic losses

### 5. Spread Filtering
- Avoids trading during high spread conditions
- Compares current spread to historical average
- Prevents poor executions during volatile periods

## Performance Monitoring

### Trade Journal
The EA creates a detailed CSV log with:
- Entry/exit times and prices
- Profit/loss for each trade
- Stop loss and take profit levels
- Trade type and symbol
- Magic number for identification

### Key Metrics to Monitor
- **Win Rate**: Percentage of profitable trades
- **Average R:R**: Actual risk-reward achieved
- **Maximum Drawdown**: Largest equity decline
- **Daily P&L**: Daily profit/loss tracking
- **Trade Frequency**: Number of trades per day/week

## Troubleshooting

### Common Issues

**No Trades Opening:**
- Check if trading session is active
- Verify symbols are available
- Ensure strategy conditions are met
- Check if daily limits are reached

**Positions Not Closing:**
- Verify stop loss/take profit levels
- Check for broker restrictions
- Ensure adequate margin

**High Spread Warnings:**
- Normal during news events
- Consider adjusting MaxSpreadMultiplier
- Check broker spread conditions

### Error Messages

**"Symbol not available":**
- Add symbol to Market Watch
- Check symbol suffix requirements
- Verify broker offers the instrument

**"Invalid lot size":**
- Check minimum/maximum lot sizes
- Verify account has sufficient margin
- Adjust MinLotSize/MaxLotSize parameters

## Best Practices

### 1. Backtesting
- Test thoroughly on historical data
- Use tick data for accurate results
- Test across different market conditions

### 2. Demo Trading
- Run on demo account first
- Monitor for at least 2 weeks
- Verify all features work correctly

### 3. Live Trading
- Start with small risk amounts
- Monitor performance closely
- Keep detailed trading records

### 4. Regular Review
- Analyze trade journal weekly
- Adjust parameters based on performance
- Stay updated with market conditions

## Support & Updates

### Version History
- Initial release with core functionality
- Added symbol-specific settings
- Enhanced risk management features
- Improved trade journaling

### Contributing
This EA is open source. Contributions are welcome for:
- Bug fixes and improvements
- Additional indicators
- New risk management features
- Performance optimizations

### Disclaimer
This EA is provided for educational purposes. Past performance does not guarantee future results. Always test thoroughly before live trading and never risk more than you can afford to lose.

---

**Author**: Christley Olubela
**Version**: 1.0  
**Last Updated**: 01/07/2025
