//+------------------------------------------------------------------+
//|                                                  TradeManager.mqh |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              v3.1 - Wider trailing steps         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

class CTradeManager
{
private:
   CTrade        m_trade;
   CPositionInfo m_pos;
   string        m_symbol;
   ulong         m_magicNumber;

   bool          m_useAutoBreakEven;
   double        m_beTriggerATRMult;  
   double        m_beLockPoints;

   bool          m_useTrailingStop;
   double        m_trailingATRMult;   
   double        m_trailingStepPoints;

   bool          m_usePartialClose;
   double        m_partialClosePercent;   

   void ConfigureFillingMode()
   {
      uint filling = (uint)SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) != 0)
         m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((filling & SYMBOL_FILLING_IOC) != 0)
         m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

public:
   CTradeManager() : m_symbol(_Symbol), m_magicNumber(202608),
                     m_useAutoBreakEven(true), m_beTriggerATRMult(1.5), m_beLockPoints(50.0), // increased from 10
                     m_useTrailingStop(true), m_trailingATRMult(1.0), m_trailingStepPoints(100.0), // increased from 20
                     m_usePartialClose(true), m_partialClosePercent(50.0) {}
   ~CTradeManager() {}

   void Init(string symbol, ulong magic,
             bool useBE = true, double beTriggerMult = 1.5, double beLock = 50,
             bool useTrailing = true, double trailMult = 1.0, double trailStep = 100,
             bool usePartial = true, double partialPct = 50.0)
   {
      m_symbol = symbol;
      m_magicNumber = magic;
      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetDeviationInPoints(30);
      ConfigureFillingMode();

      m_useAutoBreakEven    = useBE;
      m_beTriggerATRMult    = beTriggerMult;
      m_beLockPoints        = beLock;
      m_useTrailingStop     = useTrailing;
      m_trailingATRMult     = trailMult;
      m_trailingStepPoints  = trailStep;
      m_usePartialClose     = usePartial;
      m_partialClosePercent = partialPct;
   }

   bool ExecuteTrade(ENUM_SIGNAL_TYPE signal, double lots, double sl, double tp, string comment = "Apex EA")
   {
      ConfigureFillingMode();
      bool res = false;
      if(signal == SIGNAL_BUY)
      {
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         res = m_trade.Buy(lots, m_symbol, ask, sl, tp, comment);
         if(!res) { m_trade.SetTypeFilling(ORDER_FILLING_RETURN); res = m_trade.Buy(lots, m_symbol, ask, sl, tp, comment); }
      }
      else if(signal == SIGNAL_SELL)
      {
         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         res = m_trade.Sell(lots, m_symbol, bid, sl, tp, comment);
         if(!res) { m_trade.SetTypeFilling(ORDER_FILLING_RETURN); res = m_trade.Sell(lots, m_symbol, bid, sl, tp, comment); }
      }
      return res;
   }

   void PartialCloseAtTP1(ulong ticket, double tp1, double atr)
   {
      if(!m_usePartialClose) return;
      if(!m_pos.SelectByTicket(ticket)) return;

      double currentPrice = (m_pos.PositionType() == POSITION_TYPE_BUY) ?
                             SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double openPrice = m_pos.PriceOpen();
      double profitDist = (m_pos.PositionType() == POSITION_TYPE_BUY) ?
                          (currentPrice - openPrice) : (openPrice - currentPrice);

      double tp1Dist = MathAbs(tp1 - openPrice);
      if(profitDist >= tp1Dist * 0.95)
      {
         double closeLots = MathFloor(m_pos.Volume() * (m_partialClosePercent / 100.0)
                            / SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP))
                            * SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
         if(closeLots >= SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN))
         {
            m_trade.PositionClosePartial(ticket, closeLots);
            double newSL = (m_pos.PositionType() == POSITION_TYPE_BUY) ? openPrice + m_beLockPoints * _Point : openPrice - m_beLockPoints * _Point;
            m_trade.PositionModify(ticket, newSL, m_pos.TakeProfit());
         }
      }
   }

   int ReconcileActivePositions(ManagedPosition &positions[])
   {
      ArrayResize(positions, 0);
      int total = PositionsTotal(), count = 0;
      for(int i = 0; i < total; i++)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(m_pos.Symbol() != m_symbol) continue;
         if(m_pos.Magic() != m_magicNumber && m_magicNumber != 0) continue;

         ArrayResize(positions, count + 1);
         positions[count].ticket    = m_pos.Ticket();
         positions[count].type      = (m_pos.PositionType() == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
         positions[count].lots      = m_pos.Volume();
         positions[count].openPrice = m_pos.PriceOpen();
         positions[count].currentSL = m_pos.StopLoss();
         positions[count].currentTP = m_pos.TakeProfit();
         positions[count].profit    = m_pos.Profit();

         double curPrice = (positions[count].type == SIGNAL_BUY) ?
                            SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double pips = (positions[count].type == SIGNAL_BUY) ?
                        (curPrice - positions[count].openPrice) : (positions[count].openPrice - curPrice);
         positions[count].pipsProfit = pips / _Point;

         if(positions[count].currentSL == 0)
         {
            double safeSL = (positions[count].type == SIGNAL_BUY) ?
                             positions[count].openPrice - 300 * _Point :
                             positions[count].openPrice + 300 * _Point;
            m_trade.PositionModify(positions[count].ticket, safeSL, positions[count].currentTP);
            positions[count].currentSL = safeSL;
         }

         double slDist = MathAbs(positions[count].openPrice - positions[count].currentSL);
         positions[count].statusPlan = StringFormat("SL dist: %.1f pts | RR target 1:2 | %s",
                                                    slDist / _Point,
                                                    positions[count].pipsProfit >= 0 ? "In Profit" : "In Drawdown");
         count++;
      }
      return count;
   }

   void ManageOpenPositions(double atrValue)
   {
      double atr = (atrValue > 0) ? atrValue : 200 * _Point;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_magicNumber) continue;

         ulong  ticket    = m_pos.Ticket();
         double openPrice = m_pos.PriceOpen();
         double curSL     = m_pos.StopLoss();
         double curTP     = m_pos.TakeProfit();

         if(m_pos.PositionType() == POSITION_TYPE_BUY)
         {
            double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            double profitDist = bid - openPrice;

            if(m_useAutoBreakEven && profitDist >= atr * m_beTriggerATRMult)
            {
               double bePadding = MathMax(m_beLockPoints * _Point, atr * 0.25);
               double newSL = openPrice + bePadding;
               if(curSL < openPrice) m_trade.PositionModify(ticket, newSL, curTP);
            }

            if(m_useTrailingStop && profitDist >= atr * (m_beTriggerATRMult + 0.5))
            {
               double targetSL = bid - atr * m_trailingATRMult;
               if(targetSL > curSL + m_trailingStepPoints * _Point)
                  m_trade.PositionModify(ticket, targetSL, curTP);
            }
         }
         else if(m_pos.PositionType() == POSITION_TYPE_SELL)
         {
            double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            double profitDist = openPrice - ask;

            if(m_useAutoBreakEven && profitDist >= atr * m_beTriggerATRMult)
            {
               double bePadding = MathMax(m_beLockPoints * _Point, atr * 0.25);
               double newSL = openPrice - bePadding;
               if(curSL > openPrice || curSL == 0) m_trade.PositionModify(ticket, newSL, curTP);
            }

            if(m_useTrailingStop && profitDist >= atr * (m_beTriggerATRMult + 0.5))
            {
               double targetSL = ask + atr * m_trailingATRMult;
               if(targetSL < curSL - m_trailingStepPoints * _Point || curSL == 0)
                  m_trade.PositionModify(ticket, targetSL, curTP);
            }
         }
      }
   }

   int GetActivePositionsCount()
   {
      int count = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         if(m_pos.SelectByIndex(i) && m_pos.Symbol() == m_symbol && m_pos.Magic() == m_magicNumber)
            count++;
      }
      return count;
   }
};
