#include <Trade/Trade.mqh>
#include <Math/Stat/Math.mqh>
#include <Trade/DealInfo.mqh>
#include <Arrays/ArrayObj.mqh>

// Risk Management
input double RiskPerTrade = 50;          // Fixed $ risk per trade
input double RiskRewardRatio = 5;        // Risk/Reward ratio
input double StopLossATRFactor = 1.5;    // SL ATR Multiplier
input double TrailingStopATRFactor = 1.0;// Trailing SL ATR Multiplier
input int OrderExpirationBars = 5;       // Bars until limit order expires
input double MinLotSize = 0.01;          // Minimum lot size
input double MaxLotSize = 1.0;           // Maximum lot size

// Strategy Parameters
input double MinMaGap = 0.6;             // Min MA Gap (%)
input int Ma1Period = 360;               // Fast MA Period
input int Ma2Period = 20;                // Slow MA Period
input int Atr1Period = 10;               // Fast ATR Period
input int Atr2Period = 20;               // Slow ATR Period
input int RsiPeriod = 20;                // RSI Period

// Trading Settings
input bool EnableBuy = true;             // Enable Buy Trades
input bool EnableSell = true;            // Enable Sell Trades
input int MaxTradesPerSymbolTF = 1;      // Max trades per symbol/timeframe
input int MaxGlobalTrades = 15;          // Max simultaneous trades
input int MinBarsBetweenTrades = 5;      // Min bars between trades
input double LimitOrderDistance = 2.0;   // Pips from market for limit orders

// Session Settings (Lagos Time = GMT+1)
input bool EnableSession = true;         // Enable Trading Session
input int SundayOpen = 22;               // Sunday Open Hour (22:15)
input int SundayOpenMin = 15;            // Sunday Open Minute
input int DailyClose = 21;               // Daily Close Hour (21:45)
input int DailyCloseMin = 45;            // Daily Close Minute

// Prop Firm Protections
input double DailyMaxLoss = 500;         // Max daily loss ($)
input double DailyProfitTarget = 1000;   // Daily profit target ($)
input double MaxDrawdownPercent = 5.0;   // Max account drawdown (%)
input double MaxSpreadMultiplier = 3.0;  // Max spread multiplier

// Trade Journal
input bool EnableTradeJournal = true;    // Enable trade logging
input string JournalFileName = "TradeJournal.csv"; // Journal filename

// Updated symbols with 'z' suffix
string Symbols[] = {"XAUUSDz","BTCUSDz","US30z","USDJPYz","GBPJPYz","EURGBPz","ETHUSDz","USOILz","AUDJPYz","XAGUSDz","EURUSDz","GBPUSDz"};
ENUM_TIMEFRAMES Timeframes[] = {PERIOD_M5, PERIOD_M15, PERIOD_M30};

// Symbol-specific parameters
struct SymbolSettings {
   string symbol;
   double slFactor;
   double minMaGap;
   int atr1Period;
   int atr2Period;
   double rsiUpper;
   double rsiLower;
   double trailingFactor;
};

SymbolSettings settings[12] = {
   {"XAUUSDz",   2.0, 0.6, 10, 20, 70, 30, 1.0},  // Gold
   {"BTCUSDz",   1.5, 0.6, 10, 20, 75, 25, 1.0},  // Crypto
   {"US30z",     1.5, 0.8, 10, 20, 70, 30, 1.0},  // Indices
   {"USDJPYz",   1.5, 0.6,  8, 14, 70, 30, 1.0},  // FX Pair
   {"GBPJPYz",   1.5, 0.6,  8, 14, 70, 30, 1.0},  // FX Pair
   {"EURGBPz",   1.5, 0.6,  8, 14, 70, 30, 1.0},  // FX Pair
   {"ETHUSDz",   1.5, 0.6, 10, 20, 75, 25, 1.0},  // Crypto
   {"USOILz",    1.5, 0.6, 10, 20, 70, 30, 2.0},  // Oil
   {"AUDJPYz",   1.5, 0.6,  8, 14, 70, 30, 1.0},  // FX Pair
   {"XAGUSDz",   2.0, 0.6, 10, 20, 70, 30, 1.0},  // Silver
   {"EURUSDz",   1.5, 0.6,  8, 14, 70, 30, 1.0},  // FX Pair
   {"GBPUSDz",   1.5, 0.6,  8, 14, 70, 30, 1.0}   // FX Pair
};

//+------------------------------------------------------------------+
//| Pending Order Class                                              |
//+------------------------------------------------------------------+
class CPendingOrder : public CObject {
public:
   ulong ticket;
   string symbol;
   ENUM_TIMEFRAMES timeframe;
   datetime placementTime;
   int placementBar;
   ulong magic;
   
   CPendingOrder(ulong t, string s, ENUM_TIMEFRAMES tf, datetime pt, int pb, ulong m) :
      ticket(t), symbol(s), timeframe(tf), placementTime(pt), placementBar(pb), magic(m) {}
};

//+------------------------------------------------------------------+
//| Pending Order Array Class                                        |
//+------------------------------------------------------------------+
class CPendingOrderArray : public CArrayObj {
public:
   CPendingOrderArray() { m_free_mode = true; }
   
   bool AddOrder(ulong ticket, string symbol, ENUM_TIMEFRAMES tf, datetime time, int bar, ulong magic) {
      CPendingOrder* order = new CPendingOrder(ticket, symbol, tf, time, bar, magic);
      return this.Add(order);
   }
   
   void Cleanup() {
      for(int i = this.Total()-1; i >= 0; i--) {
         CPendingOrder* order = this.At(i);
         if(order == NULL) {
            this.Delete(i);
            continue;
         }
         
         if(!OrderSelect(order.ticket)) {
            this.Delete(i);
            continue;
         }
         
         if(OrderGetInteger(ORDER_STATE) != ORDER_STATE_PLACED) {
            this.Delete(i);
         }
      }
   }
   
   void CheckExpiration() {
      for(int i = this.Total()-1; i >= 0; i--) {
         CPendingOrder* order = this.At(i);
         if(order == NULL) continue;
         
         string symbol = order.symbol;
         ENUM_TIMEFRAMES tf = order.timeframe;
         
         int currentBars = iBars(symbol, tf);
         if(currentBars - order.placementBar >= OrderExpirationBars) {
            CTrade trade;
            trade.OrderDelete(order.ticket);
            Print("Order expired: ", order.ticket, " on ", symbol);
            this.Delete(i);
         }
      }
   }
   
   int CountBySymbolMagic(string symbol, ulong magic) {
      int count = 0;
      for(int i = 0; i < this.Total(); i++) {
         CPendingOrder* order = this.At(i);
         if(order != NULL && order.symbol == symbol && order.magic == magic) {
            count++;
         }
      }
      return count;
   }
};

// Global variables
double equityHigh = 0;
double equityAtStart = 0;
double dailyProfitLoss = 0;
datetime sessionStart = 0;
static ulong lastLoggedDealTicket = 0;

CPendingOrderArray activeOrders;
CTrade trade;
struct SymbolContext {
   string symbol;
   int lastTradeBar[];
   double atrCurrent[];
   datetime lastTradeTime[];
   int lastProcessedBar[];
   datetime lastOrderPlacement[];
};
SymbolContext symbolContexts[];
ulong baseMagic = 10000;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Initialize account equity tracking
   equityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
   equityAtStart = equityHigh;
   sessionStart = 0;
   
   // Initialize symbol contexts
   ArrayResize(symbolContexts, ArraySize(Symbols));
   for(int i=0; i<ArraySize(Symbols); i++) {
      symbolContexts[i].symbol = Symbols[i];
      int tfCount = ArraySize(Timeframes);
      ArrayResize(symbolContexts[i].lastTradeBar, tfCount);
      ArrayResize(symbolContexts[i].atrCurrent, tfCount);
      ArrayResize(symbolContexts[i].lastTradeTime, tfCount);
      ArrayResize(symbolContexts[i].lastProcessedBar, tfCount);
      ArrayResize(symbolContexts[i].lastOrderPlacement, tfCount);
      
      // Initialize arrays
      ArrayInitialize(symbolContexts[i].lastTradeBar, -10);
      ArrayInitialize(symbolContexts[i].lastTradeTime, 0);
      ArrayInitialize(symbolContexts[i].lastProcessedBar, 0);
      ArrayInitialize(symbolContexts[i].lastOrderPlacement, 0);
   }
   
   // Initialize trade journal
   if(EnableTradeJournal && !InitializeTradeJournal()) {
      return(INIT_FAILED);
   }
   
   // Set timer for periodic checks
   EventSetTimer(5);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   activeOrders.Clear();
}

//+------------------------------------------------------------------+
//| Trade journal initialization                                     |
//+------------------------------------------------------------------+
bool InitializeTradeJournal() {
   if(!EnableTradeJournal) return true;
   
   int handle = FileOpen(JournalFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
   if(handle == INVALID_HANDLE) {
      Print("Error creating trade journal: ", GetLastError());
      return false;
   }
   
   // Write header if new file
   if(FileSize(handle) == 0) {
      string header = "Time,Symbol,Type,Volume,Price,Profit,Comment,Magic,SL,TP";
      FileWrite(handle, header);
   }
   
   FileClose(handle);
   return true;
}

//+------------------------------------------------------------------+
//| Log deal to journal                                              |
//+------------------------------------------------------------------+
void LogDeal(ulong ticket) {
   if(!EnableTradeJournal || ticket <= lastLoggedDealTicket) return;
   
   if(HistoryDealSelect(ticket)) {
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      
      // Only log our EA's deals
      if(magic < (long)baseMagic || magic >= (long)baseMagic + 1200) return;
      
      datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      int type = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
      double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      
      // Get SL/TP from position if available
      double sl = 0, tp = 0;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN) {
         if(PositionSelectByTicket(HistoryDealGetInteger(ticket, DEAL_POSITION_ID))) {
            sl = PositionGetDouble(POSITION_SL);
            tp = PositionGetDouble(POSITION_TP);
         }
      }
      
      // Convert type to string
      string typeStr = "";
      switch(type) {
         case DEAL_TYPE_BUY: typeStr = "BUY"; break;
         case DEAL_TYPE_SELL: typeStr = "SELL"; break;
         default: typeStr = "UNKNOWN"; break;
      }
      
      // Prepare data string
      string data = StringFormat("%s,%s,%s,%.2f,%.5f,%.2f,%s,%I64d,%.5f,%.5f",
         TimeToString(time, TIME_DATE|TIME_MINUTES|TIME_SECONDS),
         symbol,
         typeStr,
         volume,
         price,
         profit,
         comment,
         magic,
         sl,
         tp
      );
      
      // Write to journal
      int handle = FileOpen(JournalFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
      if(handle != INVALID_HANDLE) {
         FileSeek(handle, 0, SEEK_END);
         FileWrite(handle, data);
         FileClose(handle);
         lastLoggedDealTicket = ticket;
      }
      else {
         Print("Journal write error: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| OnTrade event handler                                            |
//+------------------------------------------------------------------+
void OnTrade() {
   if(!EnableTradeJournal) return;
   
   // Select trade history since last logged deal
   HistorySelect(lastLoggedDealTicket, TimeCurrent() + 60);
   
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > lastLoggedDealTicket) {
         LogDeal(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Timer event handler                                              |
//+------------------------------------------------------------------+
void OnTimer() {
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Update equity high watermark
   if(currentEquity > equityHigh) equityHigh = currentEquity;
   
   // Reset daily P&L at session start
   if(IsNewTradingDay()) {
      equityAtStart = currentEquity;
      dailyProfitLoss = 0;
   }
   else {
      // Calculate current daily P&L
      dailyProfitLoss = currentEquity - equityAtStart;
   }
   
   // Clean up pending orders
   activeOrders.Cleanup();
   activeOrders.CheckExpiration();
   
   // Skip processing if session not active
   if(EnableSession && !IsTradingSession()) return;
   
   // Process only symbols/timeframes with new bars
   for(int s=0; s<ArraySize(Symbols); s++) {
      for(int t=0; t<ArraySize(Timeframes); t++) {
         string symbol = Symbols[s];
         ENUM_TIMEFRAMES tf = Timeframes[t];
         
         // Check if symbol exists
         if(!SymbolInfoInteger(symbol, SYMBOL_SELECT)) {
            Print("Symbol not available: ", symbol);
            continue;
         }
         
         int currentBars = iBars(symbol, tf);
         if(currentBars > symbolContexts[s].lastProcessedBar[t]) {
            symbolContexts[s].lastProcessedBar[t] = currentBars;
            ProcessSymbolTimeframe(symbol, tf, s, t);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trading session functions                                        |
//+------------------------------------------------------------------+
bool IsNewTradingDay() {
   datetime now = TimeGMT();
   MqlDateTime nowStruct;
   TimeToStruct(now, nowStruct);
   
   // Lagos time = GMT+1
   int lagosHour = (nowStruct.hour + 1) % 24;
   int lagosDow = nowStruct.day_of_week;
   if(lagosHour < 1) lagosDow = (lagosDow + 6) % 7; // Adjust for midnight cross
   
   // Sunday session starts at 21:15 GMT (22:15 Lagos)
   if(lagosDow == 0 && lagosHour == 22 && nowStruct.min >= 15) {
      if(sessionStart == 0 || sessionStart < now - 86400) {
         sessionStart = now;
         return true;
      }
   }
   return false;
}

bool IsTradingSession() {
   if(!EnableSession) return true;
   
   datetime now = TimeGMT();
   MqlDateTime nowStruct;
   TimeToStruct(now, nowStruct);
   
   // Lagos time = GMT+1
   int lagosHour = (nowStruct.hour + 1) % 24;
   int lagosMin = nowStruct.min;
   int lagosDow = nowStruct.day_of_week;
   if(lagosHour < 1) lagosDow = (lagosDow + 6) % 7; // Adjust for midnight cross
   
   // Sunday session starts at 21:15 GMT (22:15 Lagos)
   if(lagosDow == 0) {
      if(lagosHour < 22 || (lagosHour == 22 && lagosMin < 15)) return false;
      return true;
   }
   // Friday session ends at 20:45 GMT (21:45 Lagos)
   else if(lagosDow == 5) {
      if(lagosHour > 21 || (lagosHour == 21 && lagosMin >= 45)) return false;
      return true;
   }
   // Saturday - no trading
   else if(lagosDow == 6) {
      return false;
   }
   // Monday-Thursday: full session
   return true;
}

//+------------------------------------------------------------------+
//| Dollar risk per point calculation (FIXED)                        |
//+------------------------------------------------------------------+
double CalculateDollarRiskPerPoint(string symbol) {
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    if(tickSize == 0 || point == 0) {
        Print("Error: Invalid tick size or point value for ", symbol);
        return 0;
    }
    
    double valuePerPoint = (tickValue * point) / tickSize;
    return valuePerPoint;
}


//+------------------------------------------------------------------+
//| Money management functions (FIXED)                               |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double entry, double sl, double riskAmount) {
    if(entry == 0 || sl == 0 || entry == sl) {
        Print("Error: Invalid prices for ", symbol, " | Entry: ", entry, " | SL: ", sl);
        return 0;
    }
    
    double riskPoints = MathAbs(entry - sl);
    double dollarPerPoint = CalculateDollarRiskPerPoint(symbol);
    if(dollarPerPoint == 0) {
        Print("Error: dollarPerPoint=0 for ", symbol);
        return 0;
    }
    
    double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    if(contractSize == 0) {
        Print("Error: Contract size=0 for ", symbol);
        return 0;
    }
    
    double valuePerPointPerLot = dollarPerPoint * contractSize;
    double riskPerLot = riskPoints * valuePerPointPerLot;
    
    // Calculate lots for exact risk amount
    double lots = riskAmount / riskPerLot;
    
    // Validate lot size
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    step = (step <= 0) ? 0.01 : step;
    
    // Apply min/max limits
    if(lots < MinLotSize) lots = MinLotSize;
    if(lots > MaxLotSize) lots = MaxLotSize;
    
    // Normalize and cap lots
    lots = MathMax(minLot, MathMin(maxLot, lots));
    lots = step * MathFloor(lots/step + 0.0000001); // Avoid floating point errors
    
    return lots;
}

//+------------------------------------------------------------------+
//| Adjust SL/TP for fixed risk                                      |
//+------------------------------------------------------------------+
void AdjustRiskForFixedDollar(string symbol, double &sl, double &tp, double entry, 
                              double lot, bool isBuy, double atrValue) 
{
    double dollarPerPoint = CalculateDollarRiskPerPoint(symbol);
    if(dollarPerPoint == 0) return;
    
    double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double valuePerPointPerLot = dollarPerPoint * contractSize;
    double riskPerPoint = valuePerPointPerLot * lot;
    
    if(riskPerPoint <= 0) {
        Print("Error: Invalid risk per point for ", symbol);
        return;
    }
    
    double requiredRiskPoints = RiskPerTrade / riskPerPoint;
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    if(isBuy) {
        sl = entry - requiredRiskPoints * point;
        tp = entry + (RiskPerTrade * RiskRewardRatio) / riskPerPoint * point;
    }
    else {
        sl = entry + requiredRiskPoints * point;
        tp = entry - (RiskPerTrade * RiskRewardRatio) / riskPerPoint * point;
    }
    
    Print("Adjusted SL/TP for fixed risk: ", symbol, 
          " | Lot: ", lot, " | Risk: $", RiskPerTrade, 
          " | Reward: $", RiskPerTrade * RiskRewardRatio,
          " | New SL: ", sl, " | New TP: ", tp);
}

//+------------------------------------------------------------------+
//| Main processing function (FIXED)                                 |
//+------------------------------------------------------------------+
void ProcessSymbolTimeframe(string symbol, ENUM_TIMEFRAMES tf, int symbolIdx, int tfIdx) {
   // Skip if at max global trades
   if(PositionsTotal() >= MaxGlobalTrades) return;
   
   // Bar check for minimum trade spacing
   int bars = iBars(symbol, tf);
   if(bars - symbolContexts[symbolIdx].lastTradeBar[tfIdx] < MinBarsBetweenTrades) return;
   
   // Get symbol-specific settings
   double minMaGap = MinMaGap;
   double slFactor = StopLossATRFactor;
   double trailingFactor = TrailingStopATRFactor;
   double rsiUpper = 70;
   double rsiLower = 30;
   int atr1Period = Atr1Period;
   int atr2Period = Atr2Period;
   
   for(int i=0; i<ArraySize(settings); i++) {
      if(symbol == settings[i].symbol) {
         minMaGap = settings[i].minMaGap;
         slFactor = settings[i].slFactor;
         trailingFactor = settings[i].trailingFactor;
         rsiUpper = settings[i].rsiUpper;
         rsiLower = settings[i].rsiLower;
         atr1Period = settings[i].atr1Period;
         atr2Period = settings[i].atr2Period;
         break;
      }
   }
   
   // Get indicator handles
   int hMaFast = iMA(symbol, tf, Ma1Period, 0, MODE_SMA, PRICE_CLOSE);
   int hMaSlow = iMA(symbol, tf, Ma2Period, 0, MODE_SMA, PRICE_CLOSE);
   int hAtrFast = iATR(symbol, tf, atr1Period);
   int hAtrSlow = iATR(symbol, tf, atr2Period);
   int hRsi = iRSI(symbol, tf, RsiPeriod, PRICE_CLOSE);
   
   // Get indicator values
   double maFast[2] = {0};
   double maSlow[2] = {0};
   double atrFast[2] = {0};
   double atrSlow[2] = {0};
   double rsi[3] = {0};
   
   if(CopyBuffer(hMaFast, 0, 1, 2, maFast) < 2) {
      IndicatorRelease(hMaFast);
      return;
   }
   if(CopyBuffer(hMaSlow, 0, 1, 2, maSlow) < 2) {
      IndicatorRelease(hMaFast);
      IndicatorRelease(hMaSlow);
      return;
   }
   if(CopyBuffer(hAtrFast, 0, 1, 2, atrFast) < 2) {
      IndicatorRelease(hMaFast);
      IndicatorRelease(hMaSlow);
      IndicatorRelease(hAtrFast);
      return;
   }
   if(CopyBuffer(hAtrSlow, 0, 1, 2, atrSlow) < 2) {
      IndicatorRelease(hMaFast);
      IndicatorRelease(hMaSlow);
      IndicatorRelease(hAtrFast);
      IndicatorRelease(hAtrSlow);
      return;
   }
   if(CopyBuffer(hRsi, 0, 1, 3, rsi) < 3) {
      IndicatorRelease(hMaFast);
      IndicatorRelease(hMaSlow);
      IndicatorRelease(hAtrFast);
      IndicatorRelease(hAtrSlow);
      IndicatorRelease(hRsi);
      return;
   }
   
   double close = iClose(symbol, tf, 1);
   double gap = maFast[1] * minMaGap / 100;
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   symbolContexts[symbolIdx].atrCurrent[tfIdx] = atrFast[1];
   
   // Spread check
   long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   double currentSpread = spread * SymbolInfoDouble(symbol, SYMBOL_POINT);
   double avgSpread = iMA(symbol, PERIOD_M15, 50, 0, MODE_SMA, PRICE_TYPICAL);
   if(currentSpread > avgSpread * MaxSpreadMultiplier) {
      Print("High spread: ", currentSpread, " > ", avgSpread * MaxSpreadMultiplier, " for ", symbol);
      IndicatorRelease(hMaFast);
      IndicatorRelease(hMaSlow);
      IndicatorRelease(hAtrFast);
      IndicatorRelease(hAtrSlow);
      IndicatorRelease(hRsi);
      return;
   }
   
   // Trade conditions
   bool buyCondition = (EnableBuy && 
                      atrFast[1] < atrSlow[1] &&
                      close < maFast[1] - gap &&
                      close > maSlow[1] &&
                      rsi[2] > rsi[1] && 
                      rsi[1] < rsiUpper);
   
   bool sellCondition = (EnableSell && 
                       atrFast[1] < atrSlow[1] &&
                       close > maFast[1] + gap &&
                       close < maSlow[1] &&
                       rsi[2] < rsi[1] && 
                       rsi[1] > rsiLower);
   
   // Position management
   ManageExistingPositions(symbol, tf, symbolIdx, tfIdx, trailingFactor);
   
   // Prop firm risk checks
   if(dailyProfitLoss <= -DailyMaxLoss) {
      Print("Daily loss limit reached: ", dailyProfitLoss);
      IndicatorRelease(hMaFast);
      IndicatorRelease(hMaSlow);
      IndicatorRelease(hAtrFast);
      IndicatorRelease(hAtrSlow);
      IndicatorRelease(hRsi);
      return;
   }
   if(dailyProfitLoss >= DailyProfitTarget) {
      Print("Daily profit target reached: ", dailyProfitLoss);
      IndicatorRelease(hMaFast);
      IndicatorRelease(hMaSlow);
      IndicatorRelease(hAtrFast);
      IndicatorRelease(hAtrSlow);
      IndicatorRelease(hRsi);
      return;
   }
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = (equityHigh - currentEquity)/equityHigh*100;
   if(drawdown >= MaxDrawdownPercent) {
      Print("Max drawdown reached: ", drawdown, "%");
      IndicatorRelease(hMaFast);
      IndicatorRelease(hMaSlow);
      IndicatorRelease(hAtrFast);
      IndicatorRelease(hAtrSlow);
      IndicatorRelease(hRsi);
      return;
   }
   
   // Calculate unique magic number
   ulong magic = baseMagic + symbolIdx * 100 + tfIdx;
   
   // Count existing orders and positions
   int existingOrders = CountOrders(symbol, magic);
   
   // New trade logic
   if((buyCondition || sellCondition) && existingOrders == 0) 
   {
      // Calculate limit order prices
      double pipSize = SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;
      double buyLimitPrice = ask - LimitOrderDistance * pipSize;
      double sellLimitPrice = bid + LimitOrderDistance * pipSize;
      
      // Calculate SL/TP
      double atrValue = atrFast[1];
      double buySl = buyLimitPrice - slFactor * atrValue;
      double buyTp = buyLimitPrice + (slFactor * atrValue * RiskRewardRatio);
      double sellSl = sellLimitPrice + slFactor * atrValue;
      double sellTp = sellLimitPrice - (slFactor * atrValue * RiskRewardRatio);
      
      // Calculate expiration time
      datetime expiration = iTime(symbol, tf, 0) + OrderExpirationBars * PeriodSeconds(tf);
      
      if(buyCondition) {
         double lots = CalculateLotSize(symbol, buyLimitPrice, buySl, RiskPerTrade);
         
         // Adjust SL/TP for fixed dollar risk
         if(lots == MinLotSize || lots == MaxLotSize) {
            AdjustRiskForFixedDollar(symbol, buySl, buyTp, buyLimitPrice, lots, true, atrValue);
         }
         
         if(lots > 0) {
            trade.SetExpertMagicNumber(magic);
            if(trade.BuyLimit(lots, buyLimitPrice, symbol, buySl, buyTp, ORDER_TIME_SPECIFIED, expiration)) {
               Print("BUY LIMIT placed: ", symbol, 
                     " | Lots: ", lots, 
                     " | Price: ", buyLimitPrice, 
                     " | SL: ", buySl, 
                     " | TP: ", buyTp,
                     " | Risk: $", RiskPerTrade,
                     " | Reward: $", RiskPerTrade * RiskRewardRatio);
               symbolContexts[symbolIdx].lastTradeBar[tfIdx] = bars;
               symbolContexts[symbolIdx].lastTradeTime[tfIdx] = TimeCurrent();
               activeOrders.AddOrder(trade.ResultOrder(), symbol, tf, TimeCurrent(), bars, magic);
            }
            else {
               Print("Buy limit failed: ", GetLastError(), " for ", symbol);
            }
         }
      }
      else if(sellCondition) {
         double lots = CalculateLotSize(symbol, sellLimitPrice, sellSl, RiskPerTrade);
         
         // Adjust SL/TP for fixed dollar risk
         if(lots == MinLotSize || lots == MaxLotSize) {
            AdjustRiskForFixedDollar(symbol, sellSl, sellTp, sellLimitPrice, lots, false, atrValue);
         }
         
         if(lots > 0) {
            trade.SetExpertMagicNumber(magic);
            if(trade.SellLimit(lots, sellLimitPrice, symbol, sellSl, sellTp, ORDER_TIME_SPECIFIED, expiration)) {
               Print("SELL LIMIT placed: ", symbol, 
                     " | Lots: ", lots, 
                     " | Price: ", sellLimitPrice, 
                     " | SL: ", sellSl, 
                     " | TP: ", sellTp,
                     " | Risk: $", RiskPerTrade,
                     " | Reward: $", RiskPerTrade * RiskRewardRatio);
               symbolContexts[symbolIdx].lastTradeBar[tfIdx] = bars;
               symbolContexts[symbolIdx].lastTradeTime[tfIdx] = TimeCurrent();
               activeOrders.AddOrder(trade.ResultOrder(), symbol, tf, TimeCurrent(), bars, magic);
            }
            else {
               Print("Sell limit failed: ", GetLastError(), " for ", symbol);
            }
         }
      }
   }
   
   // Cleanup indicators
   IndicatorRelease(hMaFast);
   IndicatorRelease(hMaSlow);
   IndicatorRelease(hAtrFast);
   IndicatorRelease(hAtrSlow);
   IndicatorRelease(hRsi);
}

//+------------------------------------------------------------------+
//| Position management (FIXED)                                      |
//+------------------------------------------------------------------+
void ManageExistingPositions(string symbol, ENUM_TIMEFRAMES tf, int symbolIdx, int tfIdx, double trailingFactor) {
   ulong magic = baseMagic + symbolIdx * 100 + tfIdx;
   
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      
      if(PositionGetString(POSITION_SYMBOL) == symbol && 
         PositionGetInteger(POSITION_MAGIC) == (long)magic) 
      {
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSl = PositionGetDouble(POSITION_SL);
         double currentTp = PositionGetDouble(POSITION_TP);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double lotSize = PositionGetDouble(POSITION_VOLUME);
         double newSl = currentSl;
         double newTp = currentTp;
         
         // Calculate dollar risk per point
         double dollarPerPoint = CalculateDollarRiskPerPoint(symbol);
         if(dollarPerPoint == 0) continue;
         
         // Calculate value per point for this position
         double pointValue = lotSize * dollarPerPoint;
         if(pointValue == 0) continue;
         
         // Calculate trailing increment in points
         double trailingIncrementPoints = RiskPerTrade / pointValue;
         
         // Calculate profit units in $50 increments
         int profitUnits = (int)MathFloor(profit / RiskPerTrade);
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            if(profitUnits >= 1) {
               newSl = openPrice + profitUnits * trailingIncrementPoints;
               
               // Additional ATR-based trailing for commodities
               if(symbol == "XAUUSDz" || symbol == "USOILz" || symbol == "XAGUSDz") {
                  double atr = symbolContexts[symbolIdx].atrCurrent[tfIdx];
                  newSl = MathMax(newSl, currentPrice - trailingFactor * atr);
               }
               
               // Adjust TP to maintain 5:1 risk/reward ratio
               double slDistance = openPrice - newSl;
               newTp = openPrice + (slDistance * RiskRewardRatio);
               
               if(newSl > currentSl && newSl < currentPrice) {
                  trade.PositionModify(ticket, newSl, newTp);
                  Print("Trailing BUY ", symbol, 
                        " | New SL: ", newSl, 
                        " | New TP: ", newTp,
                        " | Risk: $", RiskPerTrade,
                        " | Reward: $", RiskPerTrade * RiskRewardRatio);
               }
            }
         }
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
            if(profitUnits >= 1) {
               newSl = openPrice - profitUnits * trailingIncrementPoints;
               
               // Additional ATR-based trailing for commodities
               if(symbol == "XAUUSDz" || symbol == "USOILz" || symbol == "XAGUSDz") {
                  double atr = symbolContexts[symbolIdx].atrCurrent[tfIdx];
                  newSl = MathMin(newSl, currentPrice + trailingFactor * atr);
               }
               
               // Adjust TP to maintain 5:1 risk/reward ratio
               double slDistance = newSl - openPrice;
               newTp = openPrice - (slDistance * RiskRewardRatio);
               
               if((newSl < currentSl || currentSl == 0) && newSl > currentPrice) {
                  trade.PositionModify(ticket, newSl, newTp);
                  Print("Trailing SELL ", symbol, 
                        " | New SL: ", newSl, 
                        " | New TP: ", newTp,
                        " | Risk: $", RiskPerTrade,
                        " | Reward: $", RiskPerTrade * RiskRewardRatio);
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Order counting including pending orders                          |
//+------------------------------------------------------------------+
int CountOrders(string symbol, ulong magic) {
   int count = 0;
   
   // Count open positions
   for(int i=0; i<PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == (long)magic) {
            count++;
         }
      }
   }
   
   // Count pending orders
   for(int i=0; i<activeOrders.Total(); i++) {
      CPendingOrder* order = activeOrders.At(i);
      if(order != NULL && order.symbol == symbol && order.magic == magic) {
         count++;
      }
   }
   
   return count;
}