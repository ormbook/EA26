//+------------------------------------------------------------------+
//|                                                  PriceAction.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              v3.1 - CHoCH / Engulfing Focused    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"

class CPriceActionTrigger
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;

public:
   CPriceActionTrigger() : m_symbol(_Symbol), m_timeframe(PERIOD_M5) {}
   ~CPriceActionTrigger() {}

   void Init(string symbol, ENUM_TIMEFRAMES tf = PERIOD_M5)
   {
      m_symbol = symbol;
      m_timeframe = tf;
   }

   PriceActionResult CheckTrigger(ENUM_SIGNAL_TYPE expectedSignal, double zoneLow, double zoneHigh, double atr)
   {
      PriceActionResult res;
      ZeroMemory(res);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, m_timeframe, 0, 10, rates);
      if(copied < 10) return res;

      MqlRates b1 = rates[1];
      MqlRates b2 = rates[2];
      MqlRates b3 = rates[3];

      double candleRange1 = b1.high - b1.low;
      if(candleRange1 < atr * 0.15) return res; 

      double body1   = MathAbs(b1.close - b1.open);
      double upper1  = b1.high - MathMax(b1.open, b1.close);
      double lower1  = MathMin(b1.open, b1.close) - b1.low;

      double zoneBuffer = atr * 0.5; // Wider buffer on M5
      bool nearZone = true;
      if(zoneHigh > 0 && zoneLow > 0)
         nearZone = (b1.low <= zoneHigh + zoneBuffer) && (b1.high >= zoneLow - zoneBuffer);

      if(!nearZone) return res;

      if(expectedSignal == SIGNAL_BUY)
      {
         // 1. Standard Bullish Engulfing
         bool engulf = (b2.close < b2.open && b1.close > b1.open &&
                        b1.close >= b2.open && b1.open <= b2.close &&
                        body1 >= atr * 0.25);

         // 2. M5 Momentum Shift (Closes above previous 2 candles)
         bool momShift = (b1.close > b1.open && b1.close > b2.high && b1.close > b3.high &&
                          body1 >= atr * 0.20);

         // 3. Pinbar (Wick >= 55% of candle)
         bool pinbar = (lower1 >= candleRange1 * 0.55 && b1.close > (b1.high - candleRange1 * 0.35) && body1 > atr * 0.15);

         if(engulf || momShift || pinbar)
         {
            res.hasTrigger   = true;
            res.signal       = SIGNAL_BUY;
            res.triggerPrice = b1.close;
            res.suggestedSL  = MathMin(b1.low, b2.low) - atr * 0.3;
            res.confidence   = engulf ? 90.0 : (momShift ? 85.0 : 80.0);
            res.patternName  = engulf ? "Bullish Engulfing" : (momShift ? "Momentum Shift" : "Strong Pinbar");
         }
      }
      else if(expectedSignal == SIGNAL_SELL)
      {
         bool engulf = (b2.close > b2.open && b1.close < b1.open &&
                        b1.close <= b2.open && b1.open >= b2.close &&
                        body1 >= atr * 0.25);

         bool momShift = (b1.close < b1.open && b1.close < b2.low && b1.close < b3.low &&
                          body1 >= atr * 0.20);

         bool pinbar = (upper1 >= candleRange1 * 0.55 && b1.close < (b1.low + candleRange1 * 0.35) && body1 > atr * 0.15);

         if(engulf || momShift || pinbar)
         {
            res.hasTrigger   = true;
            res.signal       = SIGNAL_SELL;
            res.triggerPrice = b1.close;
            res.suggestedSL  = MathMax(b1.high, b2.high) + atr * 0.3;
            res.confidence   = engulf ? 90.0 : (momShift ? 85.0 : 80.0);
            res.patternName  = engulf ? "Bearish Engulfing" : (momShift ? "Momentum Shift" : "Strong Pinbar");
         }
      }
      return res;
   }
};
