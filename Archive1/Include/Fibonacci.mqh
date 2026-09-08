//+------------------------------------------------------------------+
//|                                                    Fibonacci.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              Copyright 2026, Institutional Grade |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"

class CFibonacci
{
public:
   CFibonacci() {}
   ~CFibonacci() {}

   //--- Calculate Retracement Price Level: Level = High - Ratio * (High - Low) for Bullish retracement
   static double GetRetracement(double startPrice, double endPrice, double ratio)
   {
      return startPrice + (endPrice - startPrice) * ratio;
   }

   //--- Calculate Extension Price Level from a swing
   static double GetExtension(double lowPrice, double highPrice, double ratio, bool isUpward)
   {
      double diff = highPrice - lowPrice;
      if(isUpward)
         return highPrice + diff * (ratio - 1.0);
      else
         return lowPrice - diff * (ratio - 1.0);
   }

   //--- Check if price is within tolerance of a target Fibonacci ratio
   static bool IsRatioMatched(double actualRatio, double targetRatio, double tolerancePercent = 0.05)
   {
      double diff = MathAbs(actualRatio - targetRatio);
      return (diff <= targetRatio * tolerancePercent || diff <= 0.04);
   }

   //--- Harmonic Pattern Ratio Validator
   static bool CheckHarmonicRatio(double actual, double minRatio, double maxRatio)
   {
      return (actual >= (minRatio - 0.035) && actual <= (maxRatio + 0.035));
   }
};
