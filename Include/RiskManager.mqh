//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              v3.0 - Hard Lot Cap + Session Guard |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"
#include <Trade\AccountInfo.mqh>

class CRiskManager
{
private:
   CAccountInfo m_account;
   string       m_symbol;
   double       m_riskPercentPerTrade;
   double       m_maxDailyLossPercent;
   double       m_maxDailyProfitPercent;
   int          m_maxSpreadPoints;
   int          m_maxTradesPerDay;
   double       m_maxLotSize;           // Hard cap on lot size
   double       m_minSLPoints;          // Minimum SL distance (prevents huge lots)

   double       m_initialDailyEquity;
   datetime     m_currentDay;
   int          m_tradesToday;
   int          m_consecutiveLosses;    // Pause after N consecutive losses
   int          m_maxConsecLosses;

   bool         m_useSessionFilter;
   bool         m_useAsianFilter;       // Block Asian session completely
   int          m_sessionStartHour;     // London open: 07 UTC
   int          m_sessionEndHour;       // NY close: 21 UTC

   datetime     m_lastTradeCloseTime;
   int          m_cooldownMinutes;

public:
   CRiskManager()
      : m_symbol(_Symbol), m_riskPercentPerTrade(1.0),
        m_maxDailyLossPercent(3.0), m_maxDailyProfitPercent(6.0),
        m_maxSpreadPoints(40), m_maxTradesPerDay(3),
        m_maxLotSize(1.0), m_minSLPoints(150),
        m_initialDailyEquity(0), m_currentDay(0),
        m_tradesToday(0), m_consecutiveLosses(0), m_maxConsecLosses(3),
        m_useSessionFilter(true), m_useAsianFilter(true),
        m_sessionStartHour(7), m_sessionEndHour(21),
        m_lastTradeCloseTime(0), m_cooldownMinutes(30) {}
   ~CRiskManager() {}

   void Init(string symbol,
             double riskPct        = 1.0,
             double maxDailyLoss   = 3.0,
             double maxDailyProfit = 6.0,
             int    maxSpread      = 40,
             int    maxTrades      = 3,
             double maxLot         = 1.0,
             double minSLPts       = 150,
             bool   useSession     = true,
             int    cooldownMin    = 30,
             int    maxConsecLoss  = 3)
   {
      m_symbol = symbol;
      m_riskPercentPerTrade = riskPct;
      m_maxDailyLossPercent = maxDailyLoss;
      m_maxDailyProfitPercent = maxDailyProfit;
      m_maxSpreadPoints = maxSpread;
      m_maxTradesPerDay = maxTrades;
      m_maxLotSize = maxLot;
      m_minSLPoints = minSLPts;
      m_useSessionFilter = useSession;
      m_useAsianFilter = useSession;
      m_cooldownMinutes = cooldownMin;
      m_maxConsecLosses = maxConsecLoss;

      m_initialDailyEquity = m_account.Equity();
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      m_currentDay = dt.day;
   }

   void CheckDailyReset()
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(dt.day != m_currentDay)
      {
         m_currentDay = dt.day;
         m_initialDailyEquity = m_account.Equity();
         m_tradesToday = 0;
         m_consecutiveLosses = 0;
      }
   }

   void RegisterNewTrade()   { m_tradesToday++; }

   void RegisterTradeResult(bool isWin)
   {
      m_lastTradeCloseTime = TimeCurrent();
      if(isWin) m_consecutiveLosses = 0;
      else       m_consecutiveLosses++;
   }

   // London + New York only: 07:00 - 21:00 UTC
   bool IsActiveSession()
   {
      if(!m_useSessionFilter) return true;
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      return (dt.hour >= m_sessionStartHour && dt.hour < m_sessionEndHour);
   }

   bool IsSpreadAcceptable()
   {
      return (SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) <= m_maxSpreadPoints);
   }

   bool IsCooldownOver()
   {
      if(m_lastTradeCloseTime == 0) return true;
      return (TimeCurrent() - m_lastTradeCloseTime) >= (m_cooldownMinutes * 60);
   }

   bool IsTradingAllowed(string &reason)
   {
      CheckDailyReset();
      if(m_initialDailyEquity <= 0) m_initialDailyEquity = m_account.Equity();

      double equity = m_account.Equity();
      double pnlPct = (m_initialDailyEquity > 0) ?
                      ((equity - m_initialDailyEquity) / m_initialDailyEquity) * 100.0 : 0.0;

      if(pnlPct <= -m_maxDailyLossPercent)
      { reason = StringFormat("🔴 DAILY LOSS LIMIT %.2f%%", pnlPct); return false; }

      if(pnlPct >= m_maxDailyProfitPercent)
      { reason = StringFormat("🟢 DAILY PROFIT TARGET %.2f%% REACHED", pnlPct); return false; }

      if(m_tradesToday >= m_maxTradesPerDay)
      { reason = StringFormat("🚫 MAX %d TRADES/DAY REACHED (%d)", m_maxTradesPerDay, m_tradesToday); return false; }

      if(m_consecutiveLosses >= m_maxConsecLosses)
      { reason = StringFormat("⛔ %d CONSECUTIVE LOSSES — PAUSED FOR TODAY", m_consecutiveLosses); return false; }

      if(!IsActiveSession())
      { reason = "🌙 OUTSIDE SESSION (07:00–21:00 UTC only)"; return false; }

      if(!IsSpreadAcceptable())
      {
         long sp = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
         reason = StringFormat("📊 SPREAD %d > MAX %d pts", sp, m_maxSpreadPoints);
         return false;
      }

      if(!IsCooldownOver())
      {
         int left = m_cooldownMinutes * 60 - (int)(TimeCurrent() - m_lastTradeCloseTime);
         reason = StringFormat("⏳ COOLDOWN: %d min %d sec left", left/60, left%60);
         return false;
      }

      reason = "✅ Trading Allowed";
      return true;
   }

   // Calculate lot size with HARD CAP and minimum SL enforcement
   double CalculateLotSize(double entryPrice, double &stopLossPrice)
   {
      // Enforce minimum SL distance to prevent oversized lots
      double slDist = MathAbs(entryPrice - stopLossPrice);
      double minSLDist = m_minSLPoints * _Point;
      if(slDist < minSLDist)
      {
         // Widen SL to minimum distance
         if(stopLossPrice < entryPrice)
            stopLossPrice = entryPrice - minSLDist;
         else
            stopLossPrice = entryPrice + minSLDist;
         slDist = minSLDist;
      }

      double equity      = m_account.Equity();
      double riskMoney   = equity * (m_riskPercentPerTrade / 100.0);
      double tickSize    = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double lotStep     = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      double minLot      = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxLot      = MathMin(SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX), m_maxLotSize);

      if(tickSize <= 0 || tickValue <= 0 || lotStep <= 0) return minLot;

      double ticksAtRisk  = slDist / tickSize;
      double moneyPerLot  = ticksAtRisk * tickValue;
      if(moneyPerLot <= 0) return minLot;

      double lot = MathFloor((riskMoney / moneyPerLot) / lotStep) * lotStep;
      lot = MathMax(lot, minLot);
      lot = MathMin(lot, maxLot);  // HARD CAP — never exceed maxLot

      return lot;
   }

   double GetDailyPnLMoney()   { return m_account.Equity() - m_initialDailyEquity; }
   double GetDailyPnLPercent() { return (m_initialDailyEquity > 0) ? (GetDailyPnLMoney()/m_initialDailyEquity)*100.0 : 0.0; }
   int    GetTradesToday()     { return m_tradesToday; }
   int    GetConsecLosses()    { return m_consecutiveLosses; }
   bool   IsInSession()        { return IsActiveSession(); }
};
