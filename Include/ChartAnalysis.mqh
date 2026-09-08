//+------------------------------------------------------------------+
//|                                                ChartAnalysis.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              Copyright 2026, Institutional Grade |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"

class CChartAnalysis
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_lookbackBars;

public:
   CChartAnalysis() : m_symbol(_Symbol), m_timeframe(PERIOD_H4), m_lookbackBars(60) {}
   ~CChartAnalysis() {}

   void Init(string symbol, ENUM_TIMEFRAMES tf, int lookback = 60)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_lookbackBars = lookback;
   }

   //--- Calculate Dynamic Trend Channels
   ChannelResult CalculateChannel()
   {
      ChannelResult res;
      ZeroMemory(res);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookbackBars, rates);
      if(copied < 20) return res;

      // Linear Regression calculation
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      int n = m_lookbackBars;
      for(int i = 0; i < n; i++)
      {
         int x = n - 1 - i;
         double y = rates[i].close;
         sumX += x;
         sumY += y;
         sumXY += x * y;
         sumX2 += x * x;
      }

      double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
      double intercept = (sumY - slope * sumX) / n;

      // Calculate standard error / channel width
      double maxDeviation = 0;
      for(int i = 0; i < n; i++)
      {
         int x = n - 1 - i;
         double regPrice = intercept + slope * x;
         double devHigh = MathAbs(rates[i].high - regPrice);
         double devLow  = MathAbs(rates[i].low - regPrice);
         if(devHigh > maxDeviation) maxDeviation = devHigh;
         if(devLow > maxDeviation) maxDeviation = devLow;
      }

      double currentReg = intercept + slope * (n - 1);
      res.middleLine = currentReg;
      res.upperLine  = currentReg + maxDeviation * 0.95;
      res.lowerLine  = currentReg - maxDeviation * 0.95;
      res.slope      = slope;
      res.isValid    = true;

      double currentPrice = rates[0].close;
      double buffer = (res.upperLine - res.lowerLine) * 0.12;

      res.isNearSupport    = (MathAbs(currentPrice - res.lowerLine) <= buffer);
      res.isNearResistance = (MathAbs(currentPrice - res.upperLine) <= buffer);

      return res;
   }

   //--- Calculate Speed Resistance Lines (1/3 and 2/3 ratios)
   SpeedLinesResult CalculateSpeedLines()
   {
      SpeedLinesResult res;
      ZeroMemory(res);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookbackBars, rates);
      if(copied < 20) return res;

      // Find Major High and Low in lookback
      int highIdx = 0, lowIdx = 0;
      double maxHigh = rates[0].high, minLow = rates[0].low;

      for(int i = 1; i < copied; i++)
      {
         if(rates[i].high > maxHigh) { maxHigh = rates[i].high; highIdx = i; }
         if(rates[i].low < minLow)   { minLow = rates[i].low; lowIdx = i; }
      }

      double currentPrice = rates[0].close;
      double range = maxHigh - minLow;
      if(range <= _Point) return res;

      // Speed lines calculated from swing anchor
      if(highIdx > lowIdx) // Upward movement from Low to High
      {
         res.lineMain = maxHigh;
         res.line1_3  = maxHigh - range * (1.0 / 3.0);
         res.line2_3  = maxHigh - range * (2.0 / 3.0);
         res.isValid  = true;
         res.isNearBounce = (MathAbs(currentPrice - res.line1_3) <= range * 0.05 || MathAbs(currentPrice - res.line2_3) <= range * 0.05);
      }
      else // Downward movement from High to Low
      {
         res.lineMain = minLow;
         res.line1_3  = minLow + range * (1.0 / 3.0);
         res.line2_3  = minLow + range * (2.0 / 3.0);
         res.isValid  = true;
         res.isNearBounce = (MathAbs(currentPrice - res.line1_3) <= range * 0.05 || MathAbs(currentPrice - res.line2_3) <= range * 0.05);
      }

      return res;
   }
};
