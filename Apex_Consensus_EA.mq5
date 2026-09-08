//+------------------------------------------------------------------+
//|                                         Apex_Consensus_EA.mq5   |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              v3.5 — Speed + Accuracy Edition     |
//|                                                                  |
//|  ARCHITECTURE:                                                   |
//|  • H4 Analysis: cached, refreshed ONLY on new H4 bar close       |
//|  • M5 Trigger:  checked on EVERY new M5 bar close               |
//|  • OnTick:      only manages open positions + ATR + risk check   |
//|  => Massive speed improvement over recalculating every tick      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property version   "3.50"
#property description "Apex v3.5: Bar-cached H4 + M5 bar-close trigger. Faster, more accurate."

#include "Include\Defines.mqh"
#include "Include\Fibonacci.mqh"
#include "Include\Harmonics.mqh"
#include "Include\SMC.mqh"
#include "Include\ChartAnalysis.mqh"
#include "Include\Indicators.mqh"
#include "Include\PriceAction.mqh"
#include "Include\ConsensusEngine.mqh"
#include "Include\RiskManager.mqh"
#include "Include\TradeManager.mqh"
#include "Include\ChartVisualizer.mqh"
#include "Include\Dashboard.mqh"

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== 1. General ===";
input ulong             InpMagicNumber       = 202608;
input string            InpTradeComment      = "Apex v3.5";
input ENUM_TIMEFRAMES   InpHigherTF          = PERIOD_H1;   // Changed to H1 for faster/more trades
input ENUM_TIMEFRAMES   InpEntryTF           = PERIOD_M5;

input group "=== 2. Consensus & Quality ===";
input double            InpMinScore          = 75.0;   // 🔥 Increased to 75.0 to filter low-quality trades
input double            InpMinRR             = 1.5;

input group "=== 3. Harmonics ===";
input bool              InpEnableHarmonics   = true;
input int               InpHarmonicDepth     = 5;
input int               InpHarmonicBars      = 200;

input group "=== 4. SMC ===";
input int               InpSMCLookback       = 100;

input group "=== 5. Indicators ===";
input int               InpRSIPeriod         = 14;
input int               InpStochK            = 8;
input int               InpStochD            = 3;
input int               InpStochSlow         = 3;
input int               InpATRPeriod         = 14;

input group "=== 6. Risk Management ===";
input double            InpRiskPct           = 1.0;
input double            InpMaxDailyLoss      = 3.0;
input double            InpMaxDailyProfit    = 6.0;
input int               InpMaxSpread         = 40;
input int               InpMaxTradesDay      = 5;
input double            InpMaxLot            = 5.0;
input double            InpMinSLPoints       = 80.0;
input bool              InpUseSession        = true;
input int               InpCooldownMin       = 15;
input int               InpMaxConsecLoss     = 3;

input group "=== 7. Trade Management ===";
input bool              InpUseBE             = true;   // ✅ Re-enable BreakEven (protect capital on 6-year tests!)
input double            InpBETriggerMult     = 1.0;    // 🔥 Trigger BE faster (at 1 ATR profit)
input double            InpBELockPts         = 50.0;
input bool              InpUseTrail          = true;
input double            InpTrailMult         = 1.0;    // 🔥 Trail closer (1 ATR) to lock profits
input double            InpTrailStep         = 100.0;
input bool              InpUsePartial        = true;
input double            InpPartialPct        = 50.0;

input group "=== 8. Accuracy Filters ===";
input bool              InpRequireIndConfirm = true;    
input bool              InpRequireATRFilter  = true;    
input double            InpATRMultMin        = 0.5;
input bool              InpTrendAlignOnly    = true;    

input group "=== 9. Visuals ===";
input bool              InpFastBacktest      = false;   // ⚡ FAST MODE: disable all visuals
input bool              InpShowDash          = true;
input bool              InpDrawHarm          = true;
input bool              InpDrawSMC           = true;
input bool              InpDrawChan          = true;
input bool              InpDrawPlan          = true;
input int               InpDashX             = 20;
input int               InpDashY             = 30;

//+------------------------------------------------------------------+
//| OBJECTS                                                          |
//+------------------------------------------------------------------+
CHarmonicScanner      g_harm;
CSMCEngine            g_smc;
CChartAnalysis        g_chart;
CIndicatorEngine      g_ind;
CPriceActionTrigger   g_pa;
CConsensusEngine      g_consensus;
CRiskManager          g_risk;
CTradeManager         g_trade;
CChartVisualizer      g_vis;
CDashboard            g_dash;

//+------------------------------------------------------------------+
//| CACHED ANALYSIS RESULTS (refreshed on bar close, not every tick)|
//+------------------------------------------------------------------+
SMCAnalysisResult     g_smcRes;
HarmonicPatternResult g_harmRes;
ChannelResult         g_chanRes;
SpeedLinesResult      g_speedRes;
IndicatorResult       g_indRes;
ENUM_SIGNAL_TYPE      g_expectedSignal = SIGNAL_NONE;
double                g_zLow = 0, g_zHigh = 0;

// Last bar times for cache invalidation
datetime              g_lastH4BarTime  = 0;
datetime              g_lastM5BarTime  = 0;

//+------------------------------------------------------------------+
//| STATE                                                            |
//+------------------------------------------------------------------+
ENUM_EA_STATE         g_state = STATE_INITIALIZING;
ConsensusDecision     g_dec;
PriceActionResult     g_paRes;
ManagedPosition       g_positions[];

int                   g_atrH         = INVALID_HANDLE;
int                   g_atrAvgH      = INVALID_HANDLE;   // For ATR chop filter
double                g_atr          = 0.0;
int                   g_lastDealCount = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [APEX v3.5] Speed+Accuracy Edition Starting ===");

   g_harm.Init(_Symbol, InpHigherTF, InpHarmonicDepth, InpHarmonicBars);
   g_smc.Init(_Symbol, InpHigherTF, InpSMCLookback);
   g_chart.Init(_Symbol, InpHigherTF, 60);
   g_pa.Init(_Symbol, InpEntryTF);

   g_consensus.SetThreshold(InpMinScore);
   g_consensus.SetMinRR(InpMinRR);

   if(!g_ind.Init(_Symbol, InpHigherTF, InpRSIPeriod, InpStochK, InpStochD, InpStochSlow))
   { Print("[-] Indicator init failed"); return INIT_FAILED; }

   g_atrH = iATR(_Symbol, InpHigherTF, InpATRPeriod);
   if(g_atrH == INVALID_HANDLE) { Print("[-] ATR handle failed"); return INIT_FAILED; }

   // Average ATR handle for chop filter (20-bar average of ATR)
   g_atrAvgH = iATR(_Symbol, InpHigherTF, InpATRPeriod * 2);

   g_risk.Init(_Symbol, InpRiskPct, InpMaxDailyLoss, InpMaxDailyProfit,
               InpMaxSpread, InpMaxTradesDay, InpMaxLot, InpMinSLPoints,
               InpUseSession, InpCooldownMin, InpMaxConsecLoss);

   g_trade.Init(_Symbol, InpMagicNumber,
                InpUseBE, InpBETriggerMult, InpBELockPts,
                InpUseTrail, InpTrailMult, InpTrailStep,
                InpUsePartial, InpPartialPct);

   if(!InpFastBacktest && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      g_vis.Init(ChartID(), "Apex35_");
      g_dash.Init(ChartID(), InpDashX, InpDashY);
   }

   // Recovery
   int rec = g_trade.ReconcileActivePositions(g_positions);
   g_state = (rec > 0) ? STATE_RECOVERED_MANAGING : STATE_SCANNING_H4;
   if(rec > 0) PrintFormat("[+] RECOVERY: %d position(s) restored.", rec);

   g_lastDealCount = HistoryDealsTotal();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_atrH != INVALID_HANDLE) IndicatorRelease(g_atrH);
   if(g_atrAvgH != INVALID_HANDLE) IndicatorRelease(g_atrAvgH);
   if(!InpFastBacktest && !MQLInfoInteger(MQL_OPTIMIZATION))
   { g_vis.ClearAll(); g_dash.Clear(); }
   g_ind.Release();
   Print("=== [APEX v3.5] Stopped ===");
}

//+------------------------------------------------------------------+
void OnTick()
{
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   // Read ATR every tick (cheap — just buffer read)
   double atrBuf[1];
   if(CopyBuffer(g_atrH, 0, 1, 1, atrBuf) == 1) g_atr = atrBuf[0];
   if(g_atr <= 0) g_atr = 200 * _Point;

   // Detect closed deals for streak tracking
   CheckClosedDeals();

   // Position management runs every tick (BE, trailing, partial)
   g_trade.ManageOpenPositions(g_atr);
   int activeCount = g_trade.ReconcileActivePositions(g_positions);

   // Risk gate (fast — just comparisons, no market data)
   string riskMsg;
   if(!g_risk.IsTradingAllowed(riskMsg))
   {
      // Determine displayed state from message content
      if(StringFind(riskMsg, "SESSION") >= 0)      g_state = STATE_OUTSIDE_SESSION;
      else if(StringFind(riskMsg, "COOLDOWN") >= 0) g_state = STATE_COOLDOWN;
      else                                          g_state = STATE_RISK_LOCKED;
      RefreshDisplay(spread);
      return;
   }

   if(activeCount > 0)
   {
      g_state = (g_state == STATE_RECOVERED_MANAGING) ? STATE_RECOVERED_MANAGING : STATE_ORDER_ACTIVE;
      RefreshDisplay(spread);
      return;
   }

   // ===================================================================
   // H4 BAR CACHE: Only recalculate heavy analysis on new H4 bar close
   // ===================================================================
   datetime h4Bars[1];
   if(CopyTime(_Symbol, InpHigherTF, 0, 1, h4Bars) == 1 && h4Bars[0] != g_lastH4BarTime)
   {
      g_lastH4BarTime = h4Bars[0];
      RefreshH4Cache();
   }

   // ===================================================================
   // M5 BAR TRIGGER: Only check entry on new M5 bar close
   // ===================================================================
   datetime m5Bars[1];
   bool newM5Bar = false;
   if(CopyTime(_Symbol, InpEntryTF, 0, 1, m5Bars) == 1 && m5Bars[0] != g_lastM5BarTime)
   {
      g_lastM5BarTime = m5Bars[0];
      newM5Bar = true;
   }

   // Update state
   if(g_expectedSignal == SIGNAL_NONE) g_state = STATE_SCANNING_H4;
   else if(!g_paRes.hasTrigger)
   {
      double price = (g_expectedSignal == SIGNAL_BUY) ? ask : bid;
      g_state = (price >= g_zLow - g_atr * 0.5 && price <= g_zHigh + g_atr * 0.5) ?
                STATE_WAITING_M1_TRIGGER : STATE_WAITING_ZONE;
   }
   else g_state = STATE_WAITING_PULLBACK;

   // Only evaluate PA trigger and execute on new M5 bar
   if(newM5Bar && g_expectedSignal != SIGNAL_NONE)
   {
      // M5 Price Action Trigger
      PriceActionResult paTmp = g_pa.CheckTrigger(g_expectedSignal, g_zLow, g_zHigh, g_atr);
      g_paRes = paTmp;

      // Indicator Confirmation Filter
      if(InpRequireIndConfirm && g_paRes.hasTrigger)
      {
         bool indAgrees = CheckIndicatorConfirmation(g_expectedSignal);
         if(!indAgrees) ZeroMemory(g_paRes);
      }

      // ATR Chop Filter
      if(InpRequireATRFilter && g_paRes.hasTrigger)
      {
         if(!IsVolatilityAdequate()) ZeroMemory(g_paRes);
      }

      // Re-evaluate consensus with fresh trigger
      g_dec = g_consensus.Evaluate(g_smcRes, g_harmRes, g_chanRes, g_speedRes,
                                    g_indRes, g_paRes, bid, ask, g_atr);

      // === EXECUTION ===
      if(g_dec.isExecutable)
      {
         double entry = (g_dec.signal == SIGNAL_BUY) ? ask : bid;
         double sl    = g_dec.stopLoss;
         double lots  = g_risk.CalculateLotSize(entry, sl);

         PrintFormat("[* APEX v3.5 *] %s | Lot:%.2f | Score:%.1f%% | RR:1:%.1f | ATR:%.5f | Trigger:%s",
                     (g_dec.signal == SIGNAL_BUY ? "BUY" : "SELL"),
                     lots, g_dec.totalScore, g_dec.rrRatio, g_atr,
                     g_paRes.patternName);

         if(g_trade.ExecuteTrade(g_dec.signal, lots, sl, g_dec.tp2, InpTradeComment))
         {
            g_risk.RegisterNewTrade();
            g_state = STATE_ORDER_ACTIVE;
            ZeroMemory(g_paRes); // reset trigger so we don't double-fire
            Print("[+] Order placed!");
            if(!InpFastBacktest && InpDrawPlan) g_vis.DrawTradePlan(g_dec);
         }
         else
            PrintFormat("[-] Order FAILED. Error:%d", GetLastError());
      }
   }

   RefreshDrawings();
   RefreshDisplay(spread);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpFastBacktest && !MQLInfoInteger(MQL_OPTIMIZATION))
      RefreshDisplay(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
}

//+------------------------------------------------------------------+
// Refresh expensive H4 analysis — called only on new H4 bar close
//+------------------------------------------------------------------+
void RefreshH4Cache()
{
   g_smcRes  = g_smc.AnalyzeStructure(g_atr);
   if(InpEnableHarmonics)
      g_harmRes = g_harm.ScanHarmonics();
   else
      ZeroMemory(g_harmRes);
   g_chanRes  = g_chart.CalculateChannel();
   g_speedRes = g_chart.CalculateSpeedLines();
   g_indRes   = g_ind.Analyze();

   // Determine expected direction from H4 zone
   g_expectedSignal = SIGNAL_NONE;
   g_zLow = 0; g_zHigh = 0;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(g_harmRes.isValid && bid >= g_harmRes.przLow - g_atr && bid <= g_harmRes.przHigh + g_atr)
   {
      g_expectedSignal = g_harmRes.signal;
      g_zLow = g_harmRes.przLow; g_zHigh = g_harmRes.przHigh;
   }
   else if(g_smcRes.priceInOrderBlock)
   {
      if(!InpTrendAlignOnly ||
         (g_smcRes.activeOB.signal == SIGNAL_BUY  && g_smcRes.marketTrend != TREND_BEARISH) ||
         (g_smcRes.activeOB.signal == SIGNAL_SELL && g_smcRes.marketTrend != TREND_BULLISH))
      {
         g_expectedSignal = g_smcRes.activeOB.signal;
         g_zLow = g_smcRes.activeOB.bottom; g_zHigh = g_smcRes.activeOB.top;
      }
   }
   else if(g_smcRes.priceInFVG)
   {
      if(!InpTrendAlignOnly ||
         (g_smcRes.activeFVG.signal == SIGNAL_BUY  && g_smcRes.marketTrend != TREND_BEARISH) ||
         (g_smcRes.activeFVG.signal == SIGNAL_SELL && g_smcRes.marketTrend != TREND_BULLISH))
      {
         g_expectedSignal = g_smcRes.activeFVG.signal;
         g_zLow = g_smcRes.activeFVG.bottom; g_zHigh = g_smcRes.activeFVG.top;
      }
   }

   // Reset M5 trigger when H4 context changes
   ZeroMemory(g_paRes);

   if(!InpFastBacktest && !MQLInfoInteger(MQL_OPTIMIZATION))
      RefreshDrawings();
}

//+------------------------------------------------------------------+
// Indicator Confirmation: RSI + Stochastic must agree with signal
//+------------------------------------------------------------------+
bool CheckIndicatorConfirmation(ENUM_SIGNAL_TYPE signal)
{
   if(signal == SIGNAL_BUY)
   {
      // RSI not overbought AND Stochastic not crossing down
      bool rsiOK   = (g_indRes.rsiVal < 70.0);
      bool stochOK = (g_indRes.stochMain < 80.0 || g_indRes.stochBullishCross || g_indRes.stochSlope > 0);
      return (rsiOK && stochOK);
   }
   else if(signal == SIGNAL_SELL)
   {
      bool rsiOK   = (g_indRes.rsiVal > 30.0);
      bool stochOK = (g_indRes.stochMain > 20.0 || g_indRes.stochBearishCross || g_indRes.stochSlope < 0);
      return (rsiOK && stochOK);
   }
   return true;
}

//+------------------------------------------------------------------+
// ATR Filter: reject trades when market is choppy/flat
//+------------------------------------------------------------------+
bool IsVolatilityAdequate()
{
   if(g_atrAvgH == INVALID_HANDLE) return true;
   double avgBuf[1];
   if(CopyBuffer(g_atrAvgH, 0, 1, 1, avgBuf) != 1) return true;
   double avgATR = avgBuf[0];
   if(avgATR <= 0) return true;
   // Current ATR must be at least X% of the slower ATR average
   return (g_atr >= avgATR * InpATRMultMin);
}

//+------------------------------------------------------------------+
void CheckClosedDeals()
{
   HistorySelect(TimeCurrent() - 86400, TimeCurrent());
   int total = HistoryDealsTotal();
   if(total <= g_lastDealCount) return;

   for(int i = g_lastDealCount; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)InpMagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      g_risk.RegisterTradeResult(profit > 0);
      PrintFormat("[DEAL] #%I64u | %.2f | %s", ticket, profit, profit > 0 ? "WIN" : "LOSS");
   }
   g_lastDealCount = total;
}

//+------------------------------------------------------------------+
void RefreshDrawings()
{
   if(InpFastBacktest || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   if(InpDrawHarm && g_harmRes.isValid) g_vis.DrawHarmonicPattern(g_harmRes);
   if(InpDrawSMC)  g_vis.DrawSMCZones(g_smcRes);
   if(InpDrawChan) g_vis.DrawChannels(g_chanRes, g_speedRes);
   if(InpDrawPlan && g_dec.signal != SIGNAL_NONE) g_vis.DrawTradePlan(g_dec);
}

void RefreshDisplay(long spread)
{
   if(InpFastBacktest || MQLInfoInteger(MQL_OPTIMIZATION) || !InpShowDash) return;
   g_dash.Render(g_state, g_dec, g_smcRes, g_harmRes, g_indRes,
                 AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY),
                 g_risk.GetDailyPnLMoney(), g_risk.GetDailyPnLPercent(), spread, g_positions);
}
//+------------------------------------------------------------------+
