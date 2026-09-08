//+------------------------------------------------------------------+
//|                                                   Indicators.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              Copyright 2026, Institutional Grade |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"

class CIndicatorEngine
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_rsiHandle;
   int             m_stochHandle;

   int             m_rsiPeriod;
   int             m_stochK;
   int             m_stochD;
   int             m_stochSlowing;

public:
   CIndicatorEngine() : m_symbol(_Symbol), m_timeframe(PERIOD_H4),
                        m_rsiHandle(INVALID_HANDLE), m_stochHandle(INVALID_HANDLE),
                        m_rsiPeriod(14), m_stochK(8), m_stochD(3), m_stochSlowing(3) {}
   
   ~CIndicatorEngine()
   {
      Release();
   }

   bool Init(string symbol, ENUM_TIMEFRAMES tf, int rsiPeriod = 14, int stochK = 8, int stochD = 3, int stochSlowing = 3)
   {
      Release();
      m_symbol = symbol;
      m_timeframe = tf;
      m_rsiPeriod = rsiPeriod;
      m_stochK = stochK;
      m_stochD = stochD;
      m_stochSlowing = stochSlowing;

      m_rsiHandle = iRSI(m_symbol, m_timeframe, m_rsiPeriod, PRICE_CLOSE);
      m_stochHandle = iStochastic(m_symbol, m_timeframe, m_stochK, m_stochD, m_stochSlowing, MODE_SMA, STO_LOWHIGH);

      return (m_rsiHandle != INVALID_HANDLE && m_stochHandle != INVALID_HANDLE);
   }

   void Release()
   {
      if(m_rsiHandle != INVALID_HANDLE) { IndicatorRelease(m_rsiHandle); m_rsiHandle = INVALID_HANDLE; }
      if(m_stochHandle != INVALID_HANDLE) { IndicatorRelease(m_stochHandle); m_stochHandle = INVALID_HANDLE; }
   }

   //--- Read and analyze RSI & Stochastic
   IndicatorResult Analyze()
   {
      IndicatorResult res;
      ZeroMemory(res);

      if(m_rsiHandle == INVALID_HANDLE || m_stochHandle == INVALID_HANDLE)
         return res;

      double rsiBuffer[];
      double stochMainBuf[];
      double stochSignalBuf[];
      ArraySetAsSeries(rsiBuffer, true);
      ArraySetAsSeries(stochMainBuf, true);
      ArraySetAsSeries(stochSignalBuf, true);

      if(CopyBuffer(m_rsiHandle, 0, 0, 10, rsiBuffer) < 5) return res;
      if(CopyBuffer(m_stochHandle, 0, 0, 5, stochMainBuf) < 5) return res;
      if(CopyBuffer(m_stochHandle, 1, 0, 5, stochSignalBuf) < 5) return res;

      // 1. RSI Analysis
      res.rsiVal = rsiBuffer[0];
      res.rsiOverbought = (res.rsiVal >= 70.0);
      res.rsiOversold   = (res.rsiVal <= 30.0);

      // Simple Divergence Check
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_timeframe, 0, 10, rates) >= 10)
      {
         // Bullish Divergence: Price Lower Low while RSI Higher Low
         if(rates[0].low < rates[5].low && rsiBuffer[0] > rsiBuffer[5])
            res.rsiBullishDiv = true;

         // Bearish Divergence: Price Higher High while RSI Lower High
         if(rates[0].high > rates[5].high && rsiBuffer[0] < rsiBuffer[5])
            res.rsiBearishDiv = true;
      }

      // 2. Stochastic Analysis
      res.stochMain   = stochMainBuf[0];
      res.stochSignal = stochSignalBuf[0];
      res.stochSlope  = stochMainBuf[0] - stochMainBuf[1];

      res.stochOverbought = (res.stochMain >= 80.0);
      res.stochOversold   = (res.stochMain <= 20.0);

      // Crossovers
      res.stochBullishCross = (stochMainBuf[1] <= stochSignalBuf[1] && stochMainBuf[0] > stochSignalBuf[0]);
      res.stochBearishCross = (stochMainBuf[1] >= stochSignalBuf[1] && stochMainBuf[0] < stochSignalBuf[0]);

      // 3. Quality Score (Max 15 pts)
      double score = 0;
      if(res.rsiOversold || res.rsiOverbought) score += 5;
      if(res.rsiBullishDiv || res.rsiBearishDiv) score += 5;
      if(res.stochBullishCross || res.stochBearishCross) score += 5;
      if(score > 15.0) score = 15.0;
      res.qualityScore = score;

      return res;
   }
};
