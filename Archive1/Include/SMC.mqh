//+------------------------------------------------------------------+
//|                                                          SMC.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              v3.1 - Trend Aligned & Buffered     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"

class CSMCEngine
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_lookbackBars;

public:
   CSMCEngine() : m_symbol(_Symbol), m_timeframe(PERIOD_H4), m_lookbackBars(150) {}
   ~CSMCEngine() {}

   void Init(string symbol, ENUM_TIMEFRAMES tf, int lookback = 150)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_lookbackBars = lookback;
   }

   SMCAnalysisResult AnalyzeStructure(double atrValue = 0)
   {
      SMCAnalysisResult res;
      ZeroMemory(res);
      res.marketTrend = TREND_RANGING;
      res.qualityScore = 10.0;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookbackBars, rates);
      if(copied < 50) return res;

      double curPrice = rates[0].close;
      double atr = (atrValue > 0) ? atrValue : 200 * _Point;
      double zoneBuffer = atr * 0.5; // Wider buffer to catch more touches

      // 1. Market Trend via EMAs (20 vs 50)
      double ema20 = 0, ema50 = 0;
      for(int i = 0; i < 20; i++) ema20 += rates[i].close;
      for(int i = 0; i < 50; i++) ema50 += rates[i].close;
      ema20 /= 20.0; ema50 /= 50.0;

      if(ema20 > ema50) res.marketTrend = TREND_BULLISH;
      else if(ema20 < ema50) res.marketTrend = TREND_BEARISH;

      // 2. Swings
      int swingHighIdx = 1, swingLowIdx = 1;
      double swingHigh = rates[1].high, swingLow = rates[1].low;
      for(int i = 2; i < 60; i++)
      {
         if(rates[i].high > swingHigh) { swingHigh = rates[i].high; swingHighIdx = i; }
         if(rates[i].low  < swingLow)  { swingLow  = rates[i].low;  swingLowIdx  = i; }
      }

      if(curPrice > swingHigh) res.hasBOS = true;
      if(curPrice < swingLow)  res.hasBOS = true;

      // 3. Trend-Aligned Order Blocks
      for(int i = 3; i < 50; i++)
      {
         double candleBody = MathAbs(rates[i].close - rates[i].open);
         double nextRange  = rates[i-1].high - rates[i-1].low;

         // Bullish OB (Only if Trend is Bullish or Ranging)
         if(res.marketTrend != TREND_BEARISH && 
            rates[i].close < rates[i].open &&
            rates[i-1].close > rates[i].high &&
            candleBody > atr * 0.1 && nextRange > candleBody * 1.5)
         {
            double obTop = rates[i].open;
            double obBot = rates[i].close;

            if(curPrice >= obBot - zoneBuffer && curPrice <= obTop + zoneBuffer)
            {
               res.activeOB.signal = SIGNAL_BUY;
               res.activeOB.time   = rates[i].time;
               res.activeOB.top    = obTop;
               res.activeOB.bottom = obBot;
               res.activeOB.barIndex = i;
               res.priceInOrderBlock = true;
               res.qualityScore += 15;
               break; // Found the best recent valid OB
            }
         }

         // Bearish OB (Only if Trend is Bearish or Ranging)
         if(res.marketTrend != TREND_BULLISH &&
            rates[i].close > rates[i].open &&
            rates[i-1].close < rates[i].low &&
            candleBody > atr * 0.1 && nextRange > candleBody * 1.5)
         {
            double obTop = rates[i].close;
            double obBot = rates[i].open;

            if(curPrice >= obBot - zoneBuffer && curPrice <= obTop + zoneBuffer)
            {
               res.activeOB.signal = SIGNAL_SELL;
               res.activeOB.time   = rates[i].time;
               res.activeOB.top    = obTop;
               res.activeOB.bottom = obBot;
               res.activeOB.barIndex = i;
               res.priceInOrderBlock = true;
               res.qualityScore += 15;
               break;
            }
         }
      }

      // 4. Trend-Aligned FVG
      for(int i = 3; i < 30; i++)
      {
         // Bullish FVG
         if(res.marketTrend != TREND_BEARISH && rates[i-2].low > rates[i].high)
         {
            double fvgTop = rates[i-2].low, fvgBot = rates[i].high;
            if(curPrice >= fvgBot - zoneBuffer && curPrice <= fvgTop + zoneBuffer)
            { 
               res.activeFVG.signal = SIGNAL_BUY;
               res.activeFVG.top = fvgTop; res.activeFVG.bottom = fvgBot;
               res.priceInFVG = true; res.qualityScore += 10; 
               break;
            }
         }
         // Bearish FVG
         if(res.marketTrend != TREND_BULLISH && rates[i-2].high < rates[i].low)
         {
            double fvgTop = rates[i].low, fvgBot = rates[i-2].high;
            if(curPrice >= fvgBot - zoneBuffer && curPrice <= fvgTop + zoneBuffer)
            { 
               res.activeFVG.signal = SIGNAL_SELL;
               res.activeFVG.top = fvgTop; res.activeFVG.bottom = fvgBot;
               res.priceInFVG = true; res.qualityScore += 10; 
               break;
            }
         }
      }

      if(res.qualityScore > 35.0) res.qualityScore = 35.0;
      return res;
   }
};
