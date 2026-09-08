//+------------------------------------------------------------------+
//|                                              ConsensusEngine.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              v3.1 - Enforce Trend & Better RR    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"
#include "Harmonics.mqh"
#include "SMC.mqh"
#include "ChartAnalysis.mqh"
#include "Indicators.mqh"
#include "PriceAction.mqh"

class CConsensusEngine
{
private:
   double m_minScoreThreshold;
   double m_minRRRatio;

public:
   CConsensusEngine(double minScore = 70.0, double minRR = 1.5)
      : m_minScoreThreshold(minScore), m_minRRRatio(minRR) {}
   ~CConsensusEngine() {}

   void SetThreshold(double threshold) { m_minScoreThreshold = threshold; }
   void SetMinRR(double rr)            { m_minRRRatio = rr; }
   double GetThreshold() const         { return m_minScoreThreshold; }

   ConsensusDecision Evaluate(const SMCAnalysisResult &smc,
                              const HarmonicPatternResult &harmonic,
                              const ChannelResult &channel,
                              const SpeedLinesResult &speedLines,
                              const IndicatorResult &ind,
                              const PriceActionResult &pa,
                              double currentBid, double currentAsk,
                              double atrValue)
   {
      ConsensusDecision dec;
      ZeroMemory(dec);
      dec.signal = SIGNAL_NONE;
      dec.isExecutable = false;

      int buyVotes = 0, sellVotes = 0;

      // 1. Trend Alignment is MUST (unless harmonic)
      if(smc.marketTrend == TREND_BULLISH) buyVotes += 3;
      if(smc.marketTrend == TREND_BEARISH) sellVotes += 3;

      if(smc.activeOB.signal == SIGNAL_BUY)  buyVotes += 3;
      if(smc.activeOB.signal == SIGNAL_SELL) sellVotes += 3;
      
      if(harmonic.isValid)
      {
         if(harmonic.signal == SIGNAL_BUY)  buyVotes += 6;
         if(harmonic.signal == SIGNAL_SELL) sellVotes += 6;
      }

      if(pa.hasTrigger)
      {
         if(pa.signal == SIGNAL_BUY)  buyVotes += 3;
         if(pa.signal == SIGNAL_SELL) sellVotes += 3;
      }

      ENUM_SIGNAL_TYPE consensusSignal = (buyVotes > sellVotes) ? SIGNAL_BUY :
                                         (sellVotes > buyVotes) ? SIGNAL_SELL : SIGNAL_NONE;
                                         
      if(consensusSignal == SIGNAL_NONE) return dec;

      // STRICT FILTER: If no harmonic, we MUST align with H4 trend!
      if(!harmonic.isValid)
      {
         if(consensusSignal == SIGNAL_BUY && smc.marketTrend == TREND_BEARISH) return dec;
         if(consensusSignal == SIGNAL_SELL && smc.marketTrend == TREND_BULLISH) return dec;
      }

      double totalScore = (buyVotes > sellVotes) ? (buyVotes * 7.0) : (sellVotes * 7.0);
      if(totalScore > 100.0) totalScore = 100.0;
      if(harmonic.isValid) totalScore = MathMax(totalScore, 85.0); // Harmonics get base 85%

      double atr = (atrValue > 0) ? atrValue : 200 * _Point;
      
      // Calculate realistic SL/TP
      double slDist, tp1Dist, tp2Dist;
      
      if(harmonic.isValid && harmonic.signal == consensusSignal)
      {
         double harmSL = MathAbs(harmonic.stopLoss - harmonic.pointD.price);
         slDist  = MathMax(harmSL, atr * 0.8);
      }
      else if(pa.hasTrigger && pa.suggestedSL > 0)
      {
         slDist = MathAbs(pa.triggerPrice - pa.suggestedSL);
         slDist = MathMax(slDist, atr * 0.7);
      }
      else
      {
         slDist = atr * 1.0; 
      }
      
      // Enforce TP distances for R:R
      tp1Dist = slDist * 1.5;
      tp2Dist = slDist * 3.0; // TP2 is 1:3

      dec.signal = consensusSignal;
      dec.totalScore = totalScore;
      dec.optimalEntry = (consensusSignal == SIGNAL_BUY) ? currentAsk : currentBid;

      if(consensusSignal == SIGNAL_BUY)
      {
         dec.stopLoss = dec.optimalEntry - slDist;
         dec.tp1 = dec.optimalEntry + tp1Dist;
         dec.tp2 = dec.optimalEntry + tp2Dist;
      }
      else
      {
         dec.stopLoss = dec.optimalEntry + slDist;
         dec.tp1 = dec.optimalEntry - tp1Dist;
         dec.tp2 = dec.optimalEntry - tp2Dist;
      }

      double entry = (consensusSignal == SIGNAL_BUY) ? currentAsk : currentBid;
      double actualSLDist = MathAbs(entry - dec.stopLoss);
      double actualTP2Dist = MathAbs(dec.tp2 - entry);
      double actualRR = (actualSLDist > 0) ? (actualTP2Dist / actualSLDist) : 0;
      dec.rrRatio = actualRR;

      bool scoreOK = (totalScore >= m_minScoreThreshold);
      bool paOK    = pa.hasTrigger && pa.signal == consensusSignal;
      bool rrOK    = (actualRR >= m_minRRRatio);

      dec.isExecutable = (scoreOK && paOK && rrOK);
      dec.reason = StringFormat("Score: %.1f%% | Trend: %s | RR: 1:%.1f | %s",
                                totalScore, 
                                (smc.marketTrend == TREND_BULLISH ? "UP" : (smc.marketTrend == TREND_BEARISH ? "DOWN" : "SIDE")), 
                                actualRR,
                                dec.isExecutable ? "EXECUTABLE" : "NOT READY");
      return dec;
   }
};
