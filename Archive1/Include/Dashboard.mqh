//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              Copyright 2026, Institutional Grade |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"

class CDashboard
{
private:
   string m_prefix;
   long   m_chartId;
   int    m_x;
   int    m_y;
   int    m_width;
   int    m_height;

   //--- Helper to Create Label
   void CreateLabel(string name, int xOffset, int yOffset, string text, color clr, int fontSize = 9, bool isBold = false)
   {
      string objName = m_prefix + name;
      if(ObjectFind(m_chartId, objName) < 0)
      {
         ObjectCreate(m_chartId, objName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, objName, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(m_chartId, objName, OBJPROP_XDISTANCE, m_x + xOffset);
      ObjectSetInteger(m_chartId, objName, OBJPROP_YDISTANCE, m_y + yOffset);
      ObjectSetString(m_chartId, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, objName, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(m_chartId, objName, OBJPROP_FONT, isBold ? "Arial Bold" : "Arial");
   }

public:
   CDashboard() : m_prefix("Apex_HUD_"), m_chartId(0), m_x(20), m_y(30), m_width(400), m_height(480) {}
   ~CDashboard()
   {
      Clear();
   }

   void Init(long chartId = 0, int x = 20, int y = 30)
   {
      m_chartId = (chartId == 0) ? ChartID() : chartId;
      m_x = x;
      m_y = y;
   }

   void Clear()
   {
      ObjectsDeleteAll(m_chartId, m_prefix);
      ChartRedraw(m_chartId);
   }

   //--- Render State String
   string GetStateDescription(ENUM_EA_STATE state)
   {
      switch(state)
      {
         case STATE_SCANNING_H4:         return "🟡 [H4 SCANNING] Scanning H4 Structure & Harmonics...";
         case STATE_WAITING_ZONE:        return "🔵 [WAITING FOR ZONE] Pattern Detected - Waiting for Zone Reach";
         case STATE_WAITING_PULLBACK:    return "🟠 [WAITING FOR PULLBACK] In Zone - Waiting for Pullback Confirmation";
         case STATE_WAITING_M1_TRIGGER:  return "🟣 [WAITING FOR M5 TRIGGER] Sniper Mode - Waiting PA Rejection";
         case STATE_ORDER_ACTIVE:        return "🟢 [ORDER ACTIVE] Position Open - Managing Risk & Trailing";
         case STATE_RECOVERED_MANAGING:  return "🔄 [RECOVERED & MANAGING] Restored Active Positions - Resumed Plan";
         case STATE_RISK_LOCKED:         return "🔴 [RISK LOCKED] Daily Limit or Consec Losses - Paused Today";
         case STATE_COOLDOWN:            return "⏳ [COOLDOWN] Waiting before next setup...";
         case STATE_OUTSIDE_SESSION:     return "🌙 [OUTSIDE SESSION] Waiting for London/New York (07:00–21:00 UTC)";
         default:                        return "⚪ [INITIALIZING] Initializing System Engines...";
      }
   }

   color GetStateColor(ENUM_EA_STATE state)
   {
      switch(state)
      {
         case STATE_SCANNING_H4:        return clrGold;
         case STATE_WAITING_ZONE:       return clrDeepSkyBlue;
         case STATE_WAITING_PULLBACK:   return clrOrange;
         case STATE_WAITING_M1_TRIGGER: return clrMagenta;
         case STATE_ORDER_ACTIVE:       return clrLime;
         case STATE_RECOVERED_MANAGING: return clrTurquoise;
         case STATE_RISK_LOCKED:        return clrCrimson;
         case STATE_COOLDOWN:           return clrDarkGray;
         case STATE_OUTSIDE_SESSION:    return clrSlateBlue;
         default:                       return clrLightGray;
      }
   }

   //--- Update Full Dashboard Display
   void Render(ENUM_EA_STATE state,
               const ConsensusDecision &decision,
               const SMCAnalysisResult &smc,
               const HarmonicPatternResult &harmonic,
               const IndicatorResult &ind,
               double balance, double equity, double dailyPnL, double dailyPnLPct,
               long spread,
               const ManagedPosition &positions[])
   {
      // 1. Background Panel
      string bgName = m_prefix + "BG";
      if(ObjectFind(m_chartId, bgName) < 0)
      {
         ObjectCreate(m_chartId, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, bgName, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(m_chartId, bgName, OBJPROP_XDISTANCE, m_x);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_YDISTANCE, m_y);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_XSIZE, m_width);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_YSIZE, m_height + ArraySize(positions) * 22);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_BGCOLOR, C'16,22,32');
      ObjectSetInteger(m_chartId, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_COLOR, C'40,60,90');

      int line = 12;

      // 2. Title & Status
      CreateLabel("Title", 15, line, "⚡ APEX QUANTUM SMC & HARMONIC AI", clrCyan, 11, true);
      line += 24;

      CreateLabel("State", 15, line, GetStateDescription(state), GetStateColor(state), 9, true);
      line += 22;

      CreateLabel("Sep1", 15, line, "----------------------------------------------------------------", clrDarkGray);
      line += 16;

      // 3. Consensus Engine Score
      string scoreText = StringFormat("Consensus Score: %.1f%%  [%s]", decision.totalScore, (decision.signal == SIGNAL_BUY ? "STRONG BUY" : (decision.signal == SIGNAL_SELL ? "STRONG SELL" : "NEUTRAL")));
      color scoreClr = (decision.totalScore >= 75.0) ? clrLime : (decision.totalScore >= 50.0 ? clrGold : clrTomato);
      CreateLabel("Score", 15, line, scoreText, scoreClr, 10, true);
      line += 20;

      string breakdown = StringFormat("  SMC: %.0f/30 | Harmonics: %.0f/25 | Channels: %.0f/15 | Ind: %.0f/15 | PA: %.0f/15",
                                      decision.smcScore, decision.harmonicScore, decision.channelScore, decision.indicatorScore, decision.paScore);
      CreateLabel("Breakdown", 15, line, breakdown, clrLightSlateGray, 8);
      line += 20;

      // 4. Analysis Breakdown
      CreateLabel("Sep2", 15, line, "----------------------------------------------------------------", clrDarkGray);
      line += 16;

      string smcText = StringFormat("H4 Trend: %s | BOS: %s | CHoCH: %s | In OB: %s",
                                    (smc.marketTrend == TREND_BULLISH ? "Bullish" : (smc.marketTrend == TREND_BEARISH ? "Bearish" : "Range")),
                                    (smc.hasBOS ? "YES" : "NO"), (smc.hasCHoCH ? "YES" : "NO"), (smc.priceInOrderBlock ? "YES" : "NO"));
      CreateLabel("SMCLbl", 15, line, smcText, clrWhite, 8);
      line += 18;

      string harmText = StringFormat("Harmonic: %s (%s) | PRZ: %.2f - %.2f",
                                     CHarmonicScanner::GetPatternName(harmonic.patternType),
                                     (harmonic.isValid ? (harmonic.signal == SIGNAL_BUY ? "Bullish" : "Bearish") : "None"),
                                     harmonic.przLow, harmonic.przHigh);
      CreateLabel("HarmLbl", 15, line, harmText, clrWhite, 8);
      line += 18;

      string indText = StringFormat("RSI(14): %.1f (%s) | Stoch: %.1f / %.1f (%s)",
                                    ind.rsiVal, (ind.rsiOverbought ? "OB" : (ind.rsiOversold ? "OS" : "Mid")),
                                    ind.stochMain, ind.stochSignal, (ind.stochBullishCross ? "Bull Cross" : (ind.stochBearishCross ? "Bear Cross" : "Normal")));
      CreateLabel("IndLbl", 15, line, indText, clrWhite, 8);
      line += 22;

      // 5. Account & Risk Management
      CreateLabel("Sep3", 15, line, "----------------------------------------------------------------", clrDarkGray);
      line += 16;

      string accText = StringFormat("Balance: $%.2f | Equity: $%.2f | Spread: %d pts", balance, equity, spread);
      CreateLabel("AccLbl", 15, line, accText, clrWhite, 8);
      line += 18;

      color pnlClr = (dailyPnL >= 0) ? clrLime : clrCrimson;
      string pnlText = StringFormat("Daily PnL: $%.2f (%.2f%%) | Hard DD Limit: Active", dailyPnL, dailyPnLPct);
      CreateLabel("PnLLbl", 15, line, pnlText, pnlClr, 9, true);
      line += 24;

      // 6. Active Position Reconciliation & Plan Table
      CreateLabel("Sep4", 15, line, "----------------------------------------------------------------", clrDarkGray);
      line += 16;

      CreateLabel("PosHeader", 15, line, StringFormat("📦 ACTIVE POSITIONS & RECOVERY PLAN (%d Open):", ArraySize(positions)), clrGold, 9, true);
      line += 20;

      if(ArraySize(positions) == 0)
      {
         CreateLabel("NoPos", 15, line, "  No active positions. Scanning for next sniper setup...", clrDarkGray, 8);
         line += 20;
      }
      else
      {
         for(int i = 0; i < ArraySize(positions); i++)
         {
            string posInfo = StringFormat("  #%I64u [%s %.2f] @ %.2f | SL: %.2f | PnL: $%.2f (%.0f pts)",
                                          positions[i].ticket, (positions[i].type == SIGNAL_BUY ? "BUY" : "SELL"),
                                          positions[i].lots, positions[i].openPrice, positions[i].currentSL,
                                          positions[i].profit, positions[i].pipsProfit);
            color posClr = (positions[i].profit >= 0) ? clrLime : clrTomato;
            CreateLabel(StringFormat("Pos_%d", i), 15, line, posInfo, posClr, 8);
            line += 16;

            string planInfo = StringFormat("    ↳ Plan: %s", positions[i].statusPlan);
            CreateLabel(StringFormat("Plan_%d", i), 15, line, planInfo, clrYellowGreen, 8);
            line += 18;
         }
      }

      ChartRedraw(m_chartId);
   }
};
