//+------------------------------------------------------------------+
//|                                                    Harmonics.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              Copyright 2026, Institutional Grade |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"
#include "Fibonacci.mqh"

class CHarmonicScanner
{
private:
   string             m_symbol;
   ENUM_TIMEFRAMES    m_timeframe;
   int                m_swingDepth;
   int                m_maxBars;

   //--- Extract ZigZag/Fractal Swing Points
   bool GetSwingPoints(SwingPoint &swings[], int requiredCount = 5)
   {
      ArrayResize(swings, 0);
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, m_timeframe, 0, m_maxBars, rates);
      if(copied < m_swingDepth * 4) return false;

      // Find local peaks and valleys
      for(int i = m_swingDepth; i < copied - m_swingDepth && ArraySize(swings) < requiredCount * 2; i++)
      {
         bool isPeak = true;
         bool isValley = true;

         for(int j = 1; j <= m_swingDepth; j++)
         {
            if(rates[i].high <= rates[i - j].high || rates[i].high <= rates[i + j].high)
               isPeak = false;
            if(rates[i].low >= rates[i - j].low || rates[i].low >= rates[i + j].low)
               isValley = false;
         }

         if(isPeak)
         {
            int sz = ArraySize(swings);
            if(sz == 0 || !swings[sz - 1].isHigh)
            {
               ArrayResize(swings, sz + 1);
               swings[sz].time = rates[i].time;
               swings[sz].price = rates[i].high;
               swings[sz].barIndex = i;
               swings[sz].isHigh = true;
            }
            else if(swings[sz - 1].isHigh && rates[i].high > swings[sz - 1].price)
            {
               // Replace with higher peak
               swings[sz - 1].time = rates[i].time;
               swings[sz - 1].price = rates[i].high;
               swings[sz - 1].barIndex = i;
            }
         }
         else if(isValley)
         {
            int sz = ArraySize(swings);
            if(sz == 0 || swings[sz - 1].isHigh)
            {
               ArrayResize(swings, sz + 1);
               swings[sz].time = rates[i].time;
               swings[sz].price = rates[i].low;
               swings[sz].barIndex = i;
               swings[sz].isHigh = false;
            }
            else if(!swings[sz - 1].isHigh && rates[i].low < swings[sz - 1].price)
            {
               // Replace with lower valley
               swings[sz - 1].time = rates[i].time;
               swings[sz - 1].price = rates[i].low;
               swings[sz - 1].barIndex = i;
            }
         }
      }

      return (ArraySize(swings) >= requiredCount);
   }

public:
   CHarmonicScanner() : m_symbol(_Symbol), m_timeframe(PERIOD_H4), m_swingDepth(6), m_maxBars(300) {}
   ~CHarmonicScanner() {}

   void Init(string symbol, ENUM_TIMEFRAMES tf, int swingDepth = 6, int maxBars = 300)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_swingDepth = swingDepth;
      m_maxBars = maxBars;
   }

   //--- Scan for active Harmonic Pattern
   HarmonicPatternResult ScanHarmonics()
   {
      HarmonicPatternResult result;
      ZeroMemory(result);
      result.patternType = PATTERN_NONE;
      result.signal = SIGNAL_NONE;
      result.isValid = false;

      SwingPoint swings[];
      if(!GetSwingPoints(swings, 5))
         return result;

      // Swings array order: 0 is newest, 4 is oldest
      // We map X=4, A=3, B=2, C=1, D=current price or latest swing 0
      SwingPoint X = swings[4];
      SwingPoint A = swings[3];
      SwingPoint B = swings[2];
      SwingPoint C = swings[1];
      SwingPoint D = swings[0];

      // Leg vectors
      double XA = MathAbs(A.price - X.price);
      if(XA <= _Point) return result;

      double AB = MathAbs(B.price - A.price);
      double BC = MathAbs(C.price - B.price);
      double CD = MathAbs(D.price - C.price);
      double XD = MathAbs(D.price - X.price);
      double XC = MathAbs(C.price - X.price);

      double b_ratio_XA = AB / XA;
      double c_ratio_AB = (AB > 0) ? BC / AB : 0;
      double d_ratio_XA = XD / XA;
      double d_ratio_BC = (BC > 0) ? CD / BC : 0;
      double c_ratio_XA = XC / XA;

      bool isBullish = (!X.isHigh && A.isHigh && !B.isHigh && C.isHigh && !D.isHigh);
      bool isBearish = (X.isHigh && !A.isHigh && B.isHigh && !C.isHigh && D.isHigh);

      if(!isBullish && !isBearish)
         return result;

      ENUM_SIGNAL_TYPE signal = isBullish ? SIGNAL_BUY : SIGNAL_SELL;
      ENUM_HARMONIC_PATTERN detectedPattern = PATTERN_NONE;
      double quality = 0.0;

      // 1. Gartley (B ~ 0.618 XA, D ~ 0.786 XA)
      if(CFibonacci::CheckHarmonicRatio(b_ratio_XA, 0.58, 0.65) &&
         CFibonacci::CheckHarmonicRatio(d_ratio_XA, 0.75, 0.82))
      {
         detectedPattern = PATTERN_GARTLEY;
         quality = 92.0;
      }
      // 2. Bat (B ~ 0.382 - 0.500 XA, D ~ 0.886 XA)
      else if(CFibonacci::CheckHarmonicRatio(b_ratio_XA, 0.35, 0.53) &&
              CFibonacci::CheckHarmonicRatio(d_ratio_XA, 0.85, 0.92))
      {
         detectedPattern = PATTERN_BAT;
         quality = 94.0;
      }
      // 3. Alternate Bat (B ~ 0.382 - 0.500 XA, D ~ 1.130 XA)
      else if(CFibonacci::CheckHarmonicRatio(b_ratio_XA, 0.35, 0.53) &&
              CFibonacci::CheckHarmonicRatio(d_ratio_XA, 1.08, 1.18))
      {
         detectedPattern = PATTERN_ALT_BAT;
         quality = 90.0;
      }
      // 4. Cypher (B ~ 0.382 - 0.618 XA, C ~ 1.272 - 1.414 XA, D ~ 0.786 XC)
      else if(CFibonacci::CheckHarmonicRatio(b_ratio_XA, 0.35, 0.65) &&
              CFibonacci::CheckHarmonicRatio(c_ratio_XA, 1.22, 1.46))
      {
         double d_ratio_XC = (XC > 0) ? (MathAbs(D.price - C.price) / XC) : 0;
         if(CFibonacci::CheckHarmonicRatio(d_ratio_XC, 0.74, 0.83))
         {
            detectedPattern = PATTERN_CYPHER;
            quality = 91.0;
         }
      }
      // 5. Shark (C ~ 1.13 - 1.618 AB, D ~ 0.886 - 1.13 OX)
      else if(CFibonacci::CheckHarmonicRatio(c_ratio_AB, 1.10, 1.65) &&
              CFibonacci::CheckHarmonicRatio(d_ratio_XA, 0.85, 1.15))
      {
         detectedPattern = PATTERN_SHARK;
         quality = 89.0;
      }
      // 6. Alternate Shark (C ~ 1.13 - 1.618 AB, D ~ 1.130 OX)
      else if(CFibonacci::CheckHarmonicRatio(c_ratio_AB, 1.10, 1.65) &&
              CFibonacci::CheckHarmonicRatio(d_ratio_XA, 1.10, 1.25))
      {
         detectedPattern = PATTERN_ALT_SHARK;
         quality = 88.0;
      }

      if(detectedPattern != PATTERN_NONE)
      {
         result.patternType = detectedPattern;
         result.signal = signal;
         result.pointX = X;
         result.pointA = A;
         result.pointB = B;
         result.pointC = C;
         result.pointD = D;
         result.qualityScore = quality;
         result.isValid = true;

         // PRZ Zone (Potential Reversal Zone around D point)
         double przRange = MathAbs(C.price - D.price) * 0.15;
         result.przLow  = D.price - przRange;
         result.przHigh = D.price + przRange;

         // Take Profits based on AD Leg Fibonacci retracement
         double legAD = MathAbs(A.price - D.price);
         if(signal == SIGNAL_BUY)
         {
            result.targetTP1 = D.price + legAD * 0.382;
            result.targetTP2 = D.price + legAD * 0.618;
            result.targetTP3 = A.price;
            result.stopLoss  = (X.price < D.price ? X.price : D.price) - przRange * 0.8;
         }
         else
         {
            result.targetTP1 = D.price - legAD * 0.382;
            result.targetTP2 = D.price - legAD * 0.618;
            result.targetTP3 = A.price;
            result.stopLoss  = (X.price > D.price ? X.price : D.price) + przRange * 0.8;
         }
      }

      return result;
   }

   //--- Pattern Name String Helper
   static string GetPatternName(ENUM_HARMONIC_PATTERN p)
   {
      switch(p)
      {
         case PATTERN_GARTLEY:   return "Gartley";
         case PATTERN_BAT:       return "Bat";
         case PATTERN_ALT_BAT:   return "Alternate Bat";
         case PATTERN_CYPHER:    return "Cypher";
         case PATTERN_SHARK:     return "Shark";
         case PATTERN_ALT_SHARK: return "Alternate Shark";
         default:                return "None";
      }
   }
};
