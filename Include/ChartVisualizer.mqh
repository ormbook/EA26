//+------------------------------------------------------------------+
//|                                              ChartVisualizer.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              Copyright 2026, Institutional Grade |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"

class CChartVisualizer
{
private:
   string m_prefix;
   long   m_chartId;

public:
   CChartVisualizer() : m_prefix("Apex_Vis_"), m_chartId(0) {}
   ~CChartVisualizer()
   {
      ClearAll();
   }

   void Init(long chartId = 0, string prefix = "Apex_Vis_")
   {
      m_chartId = (chartId == 0) ? ChartID() : chartId;
      m_prefix  = prefix;
   }

   void ClearAll()
   {
      ObjectsDeleteAll(m_chartId, m_prefix);
      ChartRedraw(m_chartId);
   }

   //--- Draw Harmonic Pattern (Triangles X-A-B and B-C-D)
   void DrawHarmonicPattern(const HarmonicPatternResult &pat)
   {
      if(!pat.isValid) return;

      string xabName = m_prefix + "Harmonic_XAB";
      string bcdName = m_prefix + "Harmonic_BCD";
      string lblName = m_prefix + "Harmonic_Lbl";

      color patColor = (pat.signal == SIGNAL_BUY) ? clrDodgerBlue : clrCrimson;

      // Triangle X-A-B
      ObjectDelete(m_chartId, xabName);
      ObjectCreate(m_chartId, xabName, OBJ_TRIANGLE, 0, pat.pointX.time, pat.pointX.price, pat.pointA.time, pat.pointA.price, pat.pointB.time, pat.pointB.price);
      ObjectSetInteger(m_chartId, xabName, OBJPROP_COLOR, patColor);
      ObjectSetInteger(m_chartId, xabName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(m_chartId, xabName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(m_chartId, xabName, OBJPROP_FILL, true);
      ObjectSetInteger(m_chartId, xabName, OBJPROP_BACK, true);

      // Triangle B-C-D
      ObjectDelete(m_chartId, bcdName);
      ObjectCreate(m_chartId, bcdName, OBJ_TRIANGLE, 0, pat.pointB.time, pat.pointB.price, pat.pointC.time, pat.pointC.price, pat.pointD.time, pat.pointD.price);
      ObjectSetInteger(m_chartId, bcdName, OBJPROP_COLOR, patColor);
      ObjectSetInteger(m_chartId, bcdName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(m_chartId, bcdName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(m_chartId, bcdName, OBJPROP_FILL, true);
      ObjectSetInteger(m_chartId, bcdName, OBJPROP_BACK, true);

      // Label at D
      ObjectDelete(m_chartId, lblName);
      ObjectCreate(m_chartId, lblName, OBJ_TEXT, 0, pat.pointD.time, pat.pointD.price);
      ObjectSetString(m_chartId, lblName, OBJPROP_TEXT, StringFormat(" %s (D-Point PRZ)", CHarmonicScanner::GetPatternName(pat.patternType)));
      ObjectSetInteger(m_chartId, lblName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(m_chartId, lblName, OBJPROP_FONTSIZE, 9);

      ChartRedraw(m_chartId);
   }

   //--- Draw SMC Order Block & FVG Boxes
   void DrawSMCZones(const SMCAnalysisResult &smc)
   {
      if(smc.activeOB.time > 0)
      {
         string obName = m_prefix + "SMC_OB";
         color obColor = (smc.activeOB.signal == SIGNAL_BUY) ? C'0,90,160' : C'160,30,40';

         ObjectDelete(m_chartId, obName);
         ObjectCreate(m_chartId, obName, OBJ_RECTANGLE, 0, smc.activeOB.time, smc.activeOB.top, TimeCurrent() + PeriodSeconds(PERIOD_H4) * 8, smc.activeOB.bottom);
         ObjectSetInteger(m_chartId, obName, OBJPROP_COLOR, obColor);
         ObjectSetInteger(m_chartId, obName, OBJPROP_FILL, true);
         ObjectSetInteger(m_chartId, obName, OBJPROP_BACK, true);
         ObjectSetString(m_chartId, obName, OBJPROP_TOOLTIP, (smc.activeOB.signal == SIGNAL_BUY ? "Bullish H4 Order Block" : "Bearish H4 Order Block"));
      }

      if(smc.activeFVG.time > 0)
      {
         string fvgName = m_prefix + "SMC_FVG";
         color fvgColor = (smc.activeFVG.signal == SIGNAL_BUY) ? C'30,120,60' : C'140,60,20';

         ObjectDelete(m_chartId, fvgName);
         ObjectCreate(m_chartId, fvgName, OBJ_RECTANGLE, 0, smc.activeFVG.time, smc.activeFVG.top, TimeCurrent() + PeriodSeconds(PERIOD_H4) * 6, smc.activeFVG.bottom);
         ObjectSetInteger(m_chartId, fvgName, OBJPROP_COLOR, fvgColor);
         ObjectSetInteger(m_chartId, fvgName, OBJPROP_FILL, true);
         ObjectSetInteger(m_chartId, fvgName, OBJPROP_BACK, true);
         ObjectSetString(m_chartId, fvgName, OBJPROP_TOOLTIP, "H4 Fair Value Gap (FVG)");
      }
      ChartRedraw(m_chartId);
   }

   //--- Draw Trend Channels & Speed Lines
   void DrawChannels(const ChannelResult &chan, const SpeedLinesResult &speed)
   {
      if(chan.isValid)
      {
         datetime t1 = TimeCurrent() - PeriodSeconds(PERIOD_H4) * 50;
         datetime t2 = TimeCurrent() + PeriodSeconds(PERIOD_H4) * 10;

         string upName = m_prefix + "Chan_Up";
         string midName = m_prefix + "Chan_Mid";
         string lowName = m_prefix + "Chan_Low";

         ObjectDelete(m_chartId, upName);
         ObjectCreate(m_chartId, upName, OBJ_TREND, 0, t1, chan.upperLine, t2, chan.upperLine);
         ObjectSetInteger(m_chartId, upName, OBJPROP_COLOR, clrOrangeRed);
         ObjectSetInteger(m_chartId, upName, OBJPROP_STYLE, STYLE_DOT);

         ObjectDelete(m_chartId, midName);
         ObjectCreate(m_chartId, midName, OBJ_TREND, 0, t1, chan.middleLine, t2, chan.middleLine);
         ObjectSetInteger(m_chartId, midName, OBJPROP_COLOR, clrDarkGray);
         ObjectSetInteger(m_chartId, midName, OBJPROP_STYLE, STYLE_DASH);

         ObjectDelete(m_chartId, lowName);
         ObjectCreate(m_chartId, lowName, OBJ_TREND, 0, t1, chan.lowerLine, t2, chan.lowerLine);
         ObjectSetInteger(m_chartId, lowName, OBJPROP_COLOR, clrCornflowerBlue);
         ObjectSetInteger(m_chartId, lowName, OBJPROP_STYLE, STYLE_DOT);
      }
      ChartRedraw(m_chartId);
   }

   //--- Draw Complete Trade Plan (Entry Zone Box, SL Line, TP1, TP2, TP3 Lines)
   void DrawTradePlan(const ConsensusDecision &plan)
   {
      if(plan.signal == SIGNAL_NONE) return;

      datetime tStart = TimeCurrent() - PeriodSeconds(PERIOD_H1) * 3;
      datetime tEnd   = TimeCurrent() + PeriodSeconds(PERIOD_H1) * 20;

      // 1. Entry Zone Box
      string entryBox = m_prefix + "Plan_EntryZone";
      ObjectDelete(m_chartId, entryBox);
      ObjectCreate(m_chartId, entryBox, OBJ_RECTANGLE, 0, tStart, plan.entryZoneHigh, tEnd, plan.entryZoneLow);
      ObjectSetInteger(m_chartId, entryBox, OBJPROP_COLOR, (plan.signal == SIGNAL_BUY ? C'20,80,140' : C'140,40,60'));
      ObjectSetInteger(m_chartId, entryBox, OBJPROP_FILL, true);
      ObjectSetInteger(m_chartId, entryBox, OBJPROP_BACK, true);

      // 2. Stop Loss Line (Red)
      string slLine = m_prefix + "Plan_SL";
      ObjectDelete(m_chartId, slLine);
      ObjectCreate(m_chartId, slLine, OBJ_TREND, 0, tStart, plan.stopLoss, tEnd, plan.stopLoss);
      ObjectSetInteger(m_chartId, slLine, OBJPROP_COLOR, clrCrimson);
      ObjectSetInteger(m_chartId, slLine, OBJPROP_WIDTH, 2);
      ObjectSetInteger(m_chartId, slLine, OBJPROP_STYLE, STYLE_SOLID);

      string slText = m_prefix + "Plan_SL_Txt";
      ObjectDelete(m_chartId, slText);
      ObjectCreate(m_chartId, slText, OBJ_TEXT, 0, tEnd, plan.stopLoss);
      ObjectSetString(m_chartId, slText, OBJPROP_TEXT, StringFormat("  STOP LOSS @ %.2f", plan.stopLoss));
      ObjectSetInteger(m_chartId, slText, OBJPROP_COLOR, clrCrimson);

      // 3. Take Profit Lines (TP1, TP2, TP3)
      if(plan.tp1 > 0)
      {
         string tp1Line = m_prefix + "Plan_TP1";
         ObjectDelete(m_chartId, tp1Line);
         ObjectCreate(m_chartId, tp1Line, OBJ_TREND, 0, tStart, plan.tp1, tEnd, plan.tp1);
         ObjectSetInteger(m_chartId, tp1Line, OBJPROP_COLOR, clrLimeGreen);
         ObjectSetInteger(m_chartId, tp1Line, OBJPROP_WIDTH, 1);
         ObjectSetInteger(m_chartId, tp1Line, OBJPROP_STYLE, STYLE_DASH);

         string tp1Text = m_prefix + "Plan_TP1_Txt";
         ObjectDelete(m_chartId, tp1Text);
         ObjectCreate(m_chartId, tp1Text, OBJ_TEXT, 0, tEnd, plan.tp1);
         ObjectSetString(m_chartId, tp1Text, OBJPROP_TEXT, StringFormat("  TARGET TP1 @ %.2f", plan.tp1));
         ObjectSetInteger(m_chartId, tp1Text, OBJPROP_COLOR, clrLimeGreen);
      }

      if(plan.tp2 > 0)
      {
         string tp2Line = m_prefix + "Plan_TP2";
         ObjectDelete(m_chartId, tp2Line);
         ObjectCreate(m_chartId, tp2Line, OBJ_TREND, 0, tStart, plan.tp2, tEnd, plan.tp2);
         ObjectSetInteger(m_chartId, tp2Line, OBJPROP_COLOR, clrMediumSeaGreen);
         ObjectSetInteger(m_chartId, tp2Line, OBJPROP_WIDTH, 1);
         ObjectSetInteger(m_chartId, tp2Line, OBJPROP_STYLE, STYLE_DASH);

         string tp2Text = m_prefix + "Plan_TP2_Txt";
         ObjectDelete(m_chartId, tp2Text);
         ObjectCreate(m_chartId, tp2Text, OBJ_TEXT, 0, tEnd, plan.tp2);
         ObjectSetString(m_chartId, tp2Text, OBJPROP_TEXT, StringFormat("  TARGET TP2 @ %.2f", plan.tp2));
         ObjectSetInteger(m_chartId, tp2Text, OBJPROP_COLOR, clrMediumSeaGreen);
      }

      if(plan.tp3 > 0)
      {
         string tp3Line = m_prefix + "Plan_TP3";
         ObjectDelete(m_chartId, tp3Line);
         ObjectCreate(m_chartId, tp3Line, OBJ_TREND, 0, tStart, plan.tp3, tEnd, plan.tp3);
         ObjectSetInteger(m_chartId, tp3Line, OBJPROP_COLOR, clrGold);
         ObjectSetInteger(m_chartId, tp3Line, OBJPROP_WIDTH, 2);
         ObjectSetInteger(m_chartId, tp3Line, OBJPROP_STYLE, STYLE_SOLID);

         string tp3Text = m_prefix + "Plan_TP3_Txt";
         ObjectDelete(m_chartId, tp3Text);
         ObjectCreate(m_chartId, tp3Text, OBJ_TEXT, 0, tEnd, plan.tp3);
         ObjectSetString(m_chartId, tp3Text, OBJPROP_TEXT, StringFormat("  MAJOR TP3 @ %.2f", plan.tp3));
         ObjectSetInteger(m_chartId, tp3Text, OBJPROP_COLOR, clrGold);
      }

      ChartRedraw(m_chartId);
   }
};
