//+------------------------------------------------------------------+
//|                                             Apex_Multi_EA.mq5    |
//|            Penta-Engine: MeanRev, Trend, TrendDip, Legacy,       |
//|                          Snowball (v7.10)                        |
//+------------------------------------------------------------------+
#property copyright "AI Converted"
#property version   "7.11"

#include <Trade\Trade.mqh>
#include "Include\SMC_Engine.mqh"

#define MAX_LAYERS         10
#define MAGIC_TREND        100
#define MAGIC_TREND_PLUS   150
#define MAGIC_LEGACY_BASE  200
#define MAGIC_SNOWBALL     300
#define MAX_LEGACY_SLOTS   20  // Support up to 20 slots

enum ENUM_LEGACY_EXIT_MODE {
    EXIT_HODL = 0,        // 1. HODL (Manual Close Only)
    EXIT_REBALANCE = 1,   // 2. Rebalancing (Scale-out specific trade)
    EXIT_PORT_GOAL = 2,   // 3. Goal Setting (Close All at Portfolio Target)
    EXIT_STEP_CLOSE = 3   // 4. Step Close (Progressive Scale-out)
};

double BaseBalance = 0; // Baseline for Port Goal

input group "=== General Settings ==="
input string InpVersion      = "v7.13 Penta-Engine"; // EA Version (For Reports)
input string InpSymbols      = "XAUUSD"; // Pairs to trade
input ulong  InpMagic        = 777888;   // Base Magic
input bool   InpShowDash     = true;     // Show Dashboard

input group "=== Engine A: Mean Reversion ==="
input int    InpMaxPositions = 10;       // Max positions for Engine A
input ENUM_TIMEFRAMES InpMA_TF     = PERIOD_H4;   // MA Timeframe (Zone Filter)
input int             InpMA_Period = 200;         // MA Period (EMA)
input ENUM_TIMEFRAMES InpEntryTF   = PERIOD_M15;  // Entry TF for FVG
input double InpTP_ATR             = 0.5;         // TP (ATR multiplier)
input double InpA_MinDist_ATR      = 1.0;         // Min distance between A orders (ATR)
input bool   InpCutOnCHoCH         = true;        // Emergency H4 CHoCH cut (SELL ONLY)
input int    InpEngineA_SellStartHour = 1;        // Sell Start Hour (Broker Time)
input int    InpEngineA_SellEndHour   = 13;       // Sell End Hour (Broker Time)

input group "=== Engine B & B+: Trend Shared Settings ==="
input ENUM_TIMEFRAMES InpTrend_D1  = PERIOD_D1;    // Trend TF1: Daily
input ENUM_TIMEFRAMES InpTrend_H4  = PERIOD_H4;    // Trend TF2: H4
input double InpTrend_Trail_ATR    = 2.0;          // Trailing Stop (ATR multiplier)
input double InpTrend_MinDist_ATR  = 1.0;          // Min distance between B/B+ orders (ATR)

input group "=== Engine B: Trend Runner (Price > MA) ==="
input bool   InpEnableTrend        = true;         // Enable Engine B
input int    InpTrend_MaxPos       = 3;            // Max Engine B positions

input group "=== Engine B+: Trend Runner Dip (Price < MA) ==="
input bool   InpEnableTrendPlus    = true;         // Enable Engine B+
input int    InpTrendPlus_MaxPos   = 3;            // Max Engine B+ positions

input group "=== Engine C: Legacy (Buy Only) ==="
input bool   InpEnableLegacy       = true;         // Enable Legacy Engine
input ENUM_TIMEFRAMES InpLegacy_MA_TF = PERIOD_D1; // Legacy MA Timeframe
input int    InpLegacy_MA_Period   = 200;          // Legacy MA Period (EMA)
input double InpLegacy_DistPct     = 1.0;          // Distance to open new legacy (%)
input int    InpLegacy_MaxPos      = 5;            // Max grid positions PER SLOT for averaging
input double InpLegacy_SurvivalPct = 30.0;         // Legacy Budget PER SLOT (%)
input ENUM_LEGACY_EXIT_MODE InpLegacy_ExitMode = EXIT_STEP_CLOSE; // Legacy Exit Strategy
input double InpLegacy_HarvestPct  = 6.0;          // [Target] Profit Trigger (% of Balance)
input double InpLegacy_HarvestClose= 50.0;         // [Rebalance] % of Volume to close
input double InpLegacy_StepCloseBase = 5.0;        // [Step Close] Base % of Vol to close (e.g. 5,10,15)
input double InpPort_GoalPct       = 50.0;         // [Goal Setting] Portfolio Target (%)

input group "=== Engine D: Snowball (Breakout) ==="
input bool   InpEnableSnowball     = true;         // Enable Engine D
input ENUM_TIMEFRAMES InpEngineD_TF = PERIOD_H4;   // Breakout Timeframe (BOS)
input int    InpEngineD_MaxPos     = 5;            // Max Snowball positions
input double InpEngineD_LotMult    = 2.0;          // Lot multiplier if NO Divergence

input group "=== Risk ==="
input double InpSurvivalPct        = 50.0;         // Survive X% crash (keep 50% equity)

CTrade trade;
CSMC_Engine smc;
string symbols[];
int sym_count = 0;
datetime last_bar_time[20];
datetime last_d_bar_time[20];
int prev_m15_struct[20];

int OnInit()
{
    BaseBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    string sep = ",";
    ushort u_sep = StringGetCharacter(sep,0);
    sym_count = StringSplit(InpSymbols, u_sep, symbols);
    if(sym_count > 20) sym_count = 20;
    for(int i=0; i<sym_count; i++) {
        StringTrimLeft(symbols[i]); StringTrimRight(symbols[i]);
        SymbolSelect(symbols[i], true);
        last_bar_time[i] = 0;
        last_d_bar_time[i] = 0;
        prev_m15_struct[i] = 0;
    }
    EventSetTimer(1);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); ObjectsDeleteAll(0, "DB_"); }

//--- Magic Number helpers ---
bool IsMagicA(ulong m) { return (m >= InpMagic+1 && m <= InpMagic+MAX_LAYERS); }
bool IsMagicB(ulong m) { return (m >= InpMagic+MAGIC_TREND+1 && m <= InpMagic+MAGIC_TREND+InpTrend_MaxPos); }
bool IsMagicBPlus(ulong m) { return (m >= InpMagic+MAGIC_TREND_PLUS+1 && m <= InpMagic+MAGIC_TREND_PLUS+InpTrendPlus_MaxPos); }
bool IsMagicC(ulong m) { return (m > InpMagic + MAGIC_LEGACY_BASE && m <= InpMagic + MAGIC_LEGACY_BASE + (MAX_LEGACY_SLOTS * 10)); }
bool IsMagicD(ulong m) { return (m >= InpMagic+MAGIC_SNOWBALL+1 && m <= InpMagic+MAGIC_SNOWBALL+InpEngineD_MaxPos); }
bool IsOurMagic(ulong m) { return IsMagicA(m) || IsMagicB(m) || IsMagicBPlus(m) || IsMagicC(m) || IsMagicD(m); }

//--- Legacy Slot helpers ---
int GetLegacySlot(ulong m) {
    if(IsMagicC(m)) {
        int offset = (int)(m - InpMagic - MAGIC_LEGACY_BASE);
        return (offset / 10); // Returns 1 to MAX_LEGACY_SLOTS
    }
    return 0;
}

int CountLegacySlot(string sym, int slot) {
    int c = 0;
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong t = PositionGetTicket(j);
        ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && GetLegacySlot(m) == slot) c++;
    }
    return c;
}

double GetLowestLegacySlotPrice(string sym, int slot) {
    double min_p = -1;
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong t = PositionGetTicket(j);
        ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && GetLegacySlot(m) == slot) {
            double p = PositionGetDouble(POSITION_PRICE_OPEN);
            if(min_p == -1 || p < min_p) min_p = p;
        }
    }
    return min_p;
}

int GetActiveLegacySlot(string sym) {
    for(int s=1; s<=MAX_LEGACY_SLOTS; s++) {
        int count = 0;
        bool has_risk = false;
        
        for(int j=PositionsTotal()-1; j>=0; j--) {
            ulong t = PositionGetTicket(j);
            ulong m = PositionGetInteger(POSITION_MAGIC);
            if(PositionGetString(POSITION_SYMBOL) == sym && GetLegacySlot(m) == s) {
                count++;
                double open = PositionGetDouble(POSITION_PRICE_OPEN);
                double sl = PositionGetDouble(POSITION_SL);
                double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
                // If SL is not set, or SL is below open (has risk)
                if(sl == 0.0 || sl < open - (pt * 0.5)) has_risk = true;
            }
        }
        
        if(count == 0) return s; // Slot is completely empty, it's the active one.
        if(count > 1) return s;  // Slot is actively building a grid, cannot move on.
        if(count == 1 && has_risk) return s; // 1 trade left, but still has risk.
        
        // If count == 1 && has_risk == false, this slot is fully secured at Break-even!
        // We can safely loop to the next slot (s+1) which will become the active one.
    }
    return MAX_LEGACY_SLOTS;
}

int GetNextLayerLegacySlot(string sym, int slot) {
    bool used[10]; ArrayInitialize(used, false);
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong t = PositionGetTicket(j);
        ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && GetLegacySlot(m) == slot) {
            int layer = (int)(m - InpMagic - MAGIC_LEGACY_BASE - (slot * 10));
            if(layer >= 1 && layer <= 9) used[layer] = true;
        }
    }
    for(int k=1; k<=InpLegacy_MaxPos; k++) {
        if(!used[k]) return k;
    }
    return 0;
}

void UpdateLegacyExitsPerSlot(string sym, int slot, double current_price) {
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong ticket = PositionGetTicket(i);
        ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL) == sym && GetLegacySlot(m) == slot) {
            double open = PositionGetDouble(POSITION_PRICE_OPEN);
            // Scratch higher/older trades in this slot at break-even
            if(open > current_price) {
                double sl = PositionGetDouble(POSITION_SL);
                if(PositionGetDouble(POSITION_TP) != open) {
                    trade.PositionModify(ticket, sl, open);
                }
            }
        }
    }
}

//--- Lot helpers ---
double GetBuyLots(string sym) {
    double t = 0;
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong tk = PositionGetTicket(j); ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && IsOurMagic(m))
            if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) t += PositionGetDouble(POSITION_VOLUME);
    }
    for(int j=OrdersTotal()-1; j>=0; j--) {
        ulong tk = OrderGetTicket(j); ulong m = OrderGetInteger(ORDER_MAGIC);
        if(OrderGetString(ORDER_SYMBOL)==sym && IsOurMagic(m))
            if(OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_LIMIT) t += OrderGetDouble(ORDER_VOLUME_CURRENT);
    }
    return t;
}
double GetSellLots(string sym) {
    double t = 0;
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong tk = PositionGetTicket(j); ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicA(m)) // Only A has sells
            if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL) t += PositionGetDouble(POSITION_VOLUME);
    }
    for(int j=OrdersTotal()-1; j>=0; j--) {
        ulong tk = OrderGetTicket(j); ulong m = OrderGetInteger(ORDER_MAGIC);
        if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicA(m))
            if(OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_SELL_LIMIT) t += OrderGetDouble(ORDER_VOLUME_CURRENT);
    }
    return t;
}

double GetTotalSafeLot(string sym, double custom_pct, bool use_balance = false) {
    double price = SymbolInfoDouble(sym, SYMBOL_ASK);
    if(price <= 0) return 0;
    double tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
    double ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
    double ml1 = (price * custom_pct / 100.0) / ts * tv;
    if(ml1 == 0) return 0;
    
    double cap = use_balance ? AccountInfoDouble(ACCOUNT_BALANCE) : AccountInfoDouble(ACCOUNT_EQUITY);
    return (cap * 0.50) / ml1;
}

double GetSafeLot(string sym, bool isBuy, bool is_legacy = false) {
    double pct = is_legacy ? InpLegacy_SurvivalPct : InpSurvivalPct;
    double total_safe = GetTotalSafeLot(sym, pct, is_legacy);
    if(total_safe <= 0) return 0;
    
    double net_long = 0;
    double net_short = 0;
    
    // Calculate isolated lots based on caller type (Legacy vs Normal)
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong tk = PositionGetTicket(j); ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && IsOurMagic(m)) {
            if(is_legacy == IsMagicC(m)) {
                long type = PositionGetInteger(POSITION_TYPE);
                double v = PositionGetDouble(POSITION_VOLUME);
                if(type == POSITION_TYPE_BUY) net_long += v;
                if(type == POSITION_TYPE_SELL) net_short += v;
            }
        }
    }
    for(int j=OrdersTotal()-1; j>=0; j--) {
        ulong tk = OrderGetTicket(j); ulong m = OrderGetInteger(ORDER_MAGIC);
        if(OrderGetString(ORDER_SYMBOL)==sym && IsOurMagic(m)) {
            if(is_legacy == IsMagicC(m)) {
                long type = OrderGetInteger(ORDER_TYPE);
                double v = OrderGetDouble(ORDER_VOLUME_INITIAL);
                if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP) net_long += v;
                if(type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP) net_short += v;
            }
        }
    }
    
    if(!is_legacy) {
        // Normal engines offset longs and shorts
        double gross_long = net_long;
        double gross_short = net_short;
        net_long = MathMax(0.0, gross_long - gross_short);
        net_short = MathMax(0.0, gross_short - gross_long);
    }
    
    double buy_budget = total_safe;
    double sell_budget = total_safe / 2.0;
    
    double min_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
    double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
    
    if(isBuy) {
        if(is_legacy) {
            // Legacy Budget is PER SLOT. We do NOT subtract net_long.
            // This guarantees that Legacy 1 through 20 all get the EXACT SAME balanced lot size.
            // Risk is controlled because we hard-cap at InpLegacy_MaxPos per slot.
            double lot = buy_budget / InpLegacy_MaxPos;
            if(lot < min_lot) return min_lot;
            return MathFloor(lot / step) * step;
        } else {
            double remaining = buy_budget - net_long;
            if(remaining < min_lot && net_long > 0) return 0;
            if(remaining < min_lot) return min_lot; // Fallback for 0 trades
            
            int max_slots = InpMaxPositions + InpTrend_MaxPos + InpTrendPlus_MaxPos + InpEngineD_MaxPos;
            if(max_slots == 0) max_slots = 1;
            
            double lot = remaining / max_slots;
            if(lot < min_lot) return min_lot;
            return MathFloor(lot / step) * step;
        }
    } else {
        double remaining = sell_budget - net_short;
        if(remaining < min_lot && net_short > 0) return 0;
        
        int max_slots = is_legacy ? 1 : InpMaxPositions;
        double lot = MathMin(remaining, sell_budget / max_slots);
        lot = MathFloor(lot / step) * step;
        if(lot < min_lot) {
            if(net_short == 0) return min_lot;
            if(net_short + min_lot > sell_budget) return 0;
            lot = min_lot;
        }
        return lot;
    }
}

int CountEngineA(string sym) {
    int c = 0;
    for(int j=PositionsTotal()-1; j>=0; j--) { ulong t=PositionGetTicket(j); if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicA(PositionGetInteger(POSITION_MAGIC))) c++; }
    for(int j=OrdersTotal()-1; j>=0; j--) { ulong t=OrderGetTicket(j); if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicA(OrderGetInteger(ORDER_MAGIC))) c++; }
    return c;
}
int CountEngineB(string sym) {
    int c = 0;
    for(int j=PositionsTotal()-1; j>=0; j--) { ulong t=PositionGetTicket(j); if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicB(PositionGetInteger(POSITION_MAGIC))) c++; }
    for(int j=OrdersTotal()-1; j>=0; j--) { ulong t=OrderGetTicket(j); if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicB(OrderGetInteger(ORDER_MAGIC))) c++; }
    return c;
}
int CountEngineBPlus(string sym) {
    int c = 0;
    for(int j=PositionsTotal()-1; j>=0; j--) { ulong t=PositionGetTicket(j); if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicBPlus(PositionGetInteger(POSITION_MAGIC))) c++; }
    for(int j=OrdersTotal()-1; j>=0; j--) { ulong t=OrderGetTicket(j); if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicBPlus(OrderGetInteger(ORDER_MAGIC))) c++; }
    return c;
}
int CountEngineD(string sym) {
    int c = 0;
    for(int j=PositionsTotal()-1; j>=0; j--) { ulong t=PositionGetTicket(j); if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicD(PositionGetInteger(POSITION_MAGIC))) c++; }
    for(int j=OrdersTotal()-1; j>=0; j--) { ulong t=OrderGetTicket(j); if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicD(OrderGetInteger(ORDER_MAGIC))) c++; }
    return c;
}

int GetNextLayerA(string sym) {
    bool used[MAX_LAYERS+1]; ArrayInitialize(used, false);
    for(int j=PositionsTotal()-1; j>=0; j--) { ulong t=PositionGetTicket(j); ulong m=PositionGetInteger(POSITION_MAGIC); if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicA(m)) { int l=(int)(m-InpMagic); if(l>=1&&l<=MAX_LAYERS) used[l]=true; } }
    for(int j=OrdersTotal()-1; j>=0; j--) { ulong t=OrderGetTicket(j); ulong m=OrderGetInteger(ORDER_MAGIC); if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicA(m)) { int l=(int)(m-InpMagic); if(l>=1&&l<=MAX_LAYERS) used[l]=true; } }
    for(int k=1; k<=MAX_LAYERS; k++) if(!used[k]) return k;
    return 0;
}
int GetNextLayerB(string sym) {
    bool used[10]; ArrayInitialize(used, false);
    for(int j=PositionsTotal()-1; j>=0; j--) { ulong t=PositionGetTicket(j); ulong m=PositionGetInteger(POSITION_MAGIC); if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicB(m)) { int l=(int)(m-InpMagic-MAGIC_TREND); if(l>=1&&l<=InpTrend_MaxPos) used[l]=true; } }
    for(int j=OrdersTotal()-1; j>=0; j--) { ulong t=OrderGetTicket(j); ulong m=OrderGetInteger(ORDER_MAGIC); if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicB(m)) { int l=(int)(m-InpMagic-MAGIC_TREND); if(l>=1&&l<=InpTrend_MaxPos) used[l]=true; } }
    for(int k=1; k<=InpTrend_MaxPos; k++) if(!used[k]) return k;
    return 0;
}
int GetNextLayerBPlus(string sym) {
    bool used[10]; ArrayInitialize(used, false);
    for(int j=PositionsTotal()-1; j>=0; j--) { ulong t=PositionGetTicket(j); ulong m=PositionGetInteger(POSITION_MAGIC); if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicBPlus(m)) { int l=(int)(m-InpMagic-MAGIC_TREND_PLUS); if(l>=1&&l<=InpTrendPlus_MaxPos) used[l]=true; } }
    for(int j=OrdersTotal()-1; j>=0; j--) { ulong t=OrderGetTicket(j); ulong m=OrderGetInteger(ORDER_MAGIC); if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicBPlus(m)) { int l=(int)(m-InpMagic-MAGIC_TREND_PLUS); if(l>=1&&l<=InpTrendPlus_MaxPos) used[l]=true; } }
    for(int k=1; k<=InpTrendPlus_MaxPos; k++) if(!used[k]) return k;
    return 0;
}
int GetNextLayerD(string sym) {
    bool used[10]; ArrayInitialize(used, false);
    for(int j=PositionsTotal()-1; j>=0; j--) { ulong t=PositionGetTicket(j); ulong m=PositionGetInteger(POSITION_MAGIC); if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicD(m)) { int l=(int)(m-InpMagic-MAGIC_SNOWBALL); if(l>=1&&l<=InpEngineD_MaxPos) used[l]=true; } }
    for(int j=OrdersTotal()-1; j>=0; j--) { ulong t=OrderGetTicket(j); ulong m=OrderGetInteger(ORDER_MAGIC); if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicD(m)) { int l=(int)(m-InpMagic-MAGIC_SNOWBALL); if(l>=1&&l<=InpEngineD_MaxPos) used[l]=true; } }
    for(int k=1; k<=InpEngineD_MaxPos; k++) if(!used[k]) return k;
    return 0;
}

double GetMA(string sym, ENUM_TIMEFRAMES tf, int period) {
    int h = iMA(sym, tf, period, 0, MODE_EMA, PRICE_CLOSE);
    double buf[]; CopyBuffer(h, 0, 0, 1, buf); IndicatorRelease(h);
    return (ArraySize(buf) > 0) ? buf[0] : 0;
}

//--- Helper: Get extreme prices for Engine A to prevent buying higher or selling lower ---
double GetLowestABuy(string sym) {
    double min_p = -1;
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong t = PositionGetTicket(j); ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicA(m) && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) {
            double p = PositionGetDouble(POSITION_PRICE_OPEN);
            if(min_p == -1 || p < min_p) min_p = p;
        }
    }
    for(int j=OrdersTotal()-1; j>=0; j--) {
        ulong t = OrderGetTicket(j); ulong m = OrderGetInteger(ORDER_MAGIC);
        if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicA(m) && OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_LIMIT) {
            double p = OrderGetDouble(ORDER_PRICE_OPEN);
            if(min_p == -1 || p < min_p) min_p = p;
        }
    }
    return min_p;
}

double GetHighestASell(string sym) {
    double max_p = -1;
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong t = PositionGetTicket(j); ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicA(m) && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL) {
            double p = PositionGetDouble(POSITION_PRICE_OPEN);
            if(max_p == -1 || p > max_p) max_p = p;
        }
    }
    for(int j=OrdersTotal()-1; j>=0; j--) {
        ulong t = OrderGetTicket(j); ulong m = OrderGetInteger(ORDER_MAGIC);
        if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicA(m) && OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_SELL_LIMIT) {
            double p = OrderGetDouble(ORDER_PRICE_OPEN);
            if(max_p == -1 || p > max_p) max_p = p;
        }
    }
    return max_p;
}

//--- Check if price is too close to an existing order/position of the same engine ---
bool IsTooClose(string sym, double target_price, int magic_base, int max_pos, double dist_atr_mult) {
    double atr[]; int ah = iATR(sym, PERIOD_H1, 14);
    CopyBuffer(ah, 0, 0, 1, atr); IndicatorRelease(ah);
    double min_dist = (ArraySize(atr)>0) ? atr[0] * dist_atr_mult : 0;
    
    if(min_dist == 0) return false;
    
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong t=PositionGetTicket(j); ulong m=PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && m >= InpMagic+magic_base+1 && m <= InpMagic+magic_base+max_pos) {
            double open = PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(open - target_price) < min_dist) return true;
        }
    }
    for(int j=OrdersTotal()-1; j>=0; j--) {
        ulong t=OrderGetTicket(j); ulong m=OrderGetInteger(ORDER_MAGIC);
        if(OrderGetString(ORDER_SYMBOL)==sym && m >= InpMagic+magic_base+1 && m <= InpMagic+magic_base+max_pos) {
            double open = OrderGetDouble(ORDER_PRICE_OPEN);
            if(MathAbs(open - target_price) < min_dist) return true;
        }
    }
    return false;
}

void OnTimer()
{
    CheckPortGoal();
    
    bool isFastTest = (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));
    if(InpShowDash && !isFastTest) DrawDashboard();
    
    for(int i=0; i<sym_count; i++) {
        string sym = symbols[i];
        if(!SymbolInfoInteger(sym, SYMBOL_SELECT)) continue;
        
        double ma = GetMA(sym, InpMA_TF, InpMA_Period);
        double bid = SymbolInfoDouble(sym, SYMBOL_BID);
        double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
        if(ma <= 0) continue;
        
        // FAST LOOP: TP + MA Exit Guard + Trend Trailing
        ManageEngineA(sym, ma, bid, ask);
        ManageEnginesTrend(sym, bid, ask); 
        ManageEngineC(sym, bid);
        ManageEngineD(sym, bid, ask);
        
        // SLOW LOOP: New M15 candle
        datetime current_bar = iTime(sym, InpEntryTF, 0);
        if(current_bar == last_bar_time[i] && current_bar != 0) continue;
        last_bar_time[i] = current_bar;
        
        int h4_struct = smc.GetMarketStructure(sym, InpTrend_H4);
        int m15_struct = smc.GetMarketStructure(sym, InpEntryTF);
        
        // H4 CHoCH cut for Engine A (SELL ONLY) and Engine D (BUY ONLY)
        if(InpCutOnCHoCH) {
            for(int j=PositionsTotal()-1; j>=0; j--) {
                ulong t=PositionGetTicket(j); ulong m=PositionGetInteger(POSITION_MAGIC);
                if(PositionGetString(POSITION_SYMBOL)==sym) {
                    long tp=PositionGetInteger(POSITION_TYPE);
                    if(IsMagicA(m) && tp==POSITION_TYPE_SELL && h4_struct==1) trade.PositionClose(t);
                    if(IsMagicD(m) && tp==POSITION_TYPE_BUY && h4_struct==-1) trade.PositionClose(t);
                }
            }
            for(int j=OrdersTotal()-1; j>=0; j--) {
                ulong t=OrderGetTicket(j); ulong m=OrderGetInteger(ORDER_MAGIC);
                if(OrderGetString(ORDER_SYMBOL)==sym) {
                    long tp=OrderGetInteger(ORDER_TYPE);
                    if(IsMagicA(m) && tp==ORDER_TYPE_SELL_LIMIT && h4_struct==1) trade.OrderDelete(t);
                }
            }
        }
        
        CleanUpPendingOrders(sym);
        
        //=== ENGINE A: Mean Reversion ===
        int zone = (bid < ma) ? 1 : -1;
        
        bool fresh_signal = false;
        if(m15_struct != prev_m15_struct[i] && m15_struct == zone) fresh_signal = true;
        if(m15_struct == zone && prev_m15_struct[i] == zone) {
            SMC_Zone tf[]; int fc = smc.GetActiveFVGs(sym, InpEntryTF, (zone==1), tf, 1);
            if(fc > 0 && tf[0].time_start >= iTime(sym, InpEntryTF, 1)) fresh_signal = true;
        }
        prev_m15_struct[i] = m15_struct;
        
        if(fresh_signal && CountEngineA(sym) < InpMaxPositions) {
            int nl = GetNextLayerA(sym);
            if(nl > 0) {
                double lot = GetSafeLot(sym, (zone==1));
                if(lot > 0) {
                    if(zone == 1) {
                        SMC_Zone bf[]; int bc = smc.GetActiveFVGs(sym, InpEntryTF, true, bf, 3);
                        if(bc > 0 && !IsTooClose(sym, bf[0].poc, 0, InpMaxPositions, InpA_MinDist_ATR)) {
                            double lowest_buy = GetLowestABuy(sym);
                            if(lowest_buy == -1 || bf[0].poc < lowest_buy) {
                                trade.SetExpertMagicNumber(InpMagic+nl); 
                                trade.BuyLimit(lot, bf[0].poc, sym, 0,0, ORDER_TIME_GTC, 0, "A_BuyDip"); 
                            }
                        }
                    } else {
                        // TIME SESSION FILTER FOR SELLS
                        MqlDateTime dt; TimeCurrent(dt);
                        bool is_valid_time = false;
                        if(InpEngineA_SellStartHour <= InpEngineA_SellEndHour) {
                            if(dt.hour >= InpEngineA_SellStartHour && dt.hour <= InpEngineA_SellEndHour) is_valid_time = true;
                        } else {
                            if(dt.hour >= InpEngineA_SellStartHour || dt.hour <= InpEngineA_SellEndHour) is_valid_time = true;
                        }
                        
                        if(is_valid_time) {
                            SMC_Zone sf[]; int sc = smc.GetActiveFVGs(sym, InpEntryTF, false, sf, 3);
                            if(sc > 0 && !IsTooClose(sym, sf[0].poc, 0, InpMaxPositions, InpA_MinDist_ATR)) {
                                double highest_sell = GetHighestASell(sym);
                                if(highest_sell == -1 || sf[0].poc > highest_sell) {
                                    trade.SetExpertMagicNumber(InpMagic+nl); 
                                    trade.SellLimit(lot, sf[0].poc, sym, 0,0, ORDER_TIME_GTC, 0, "A_SellTop"); 
                                }
                            }
                        }
                    }
                }
            }
        }
        
        //=== ENGINE B: Trend Runner (Price > MA) ===
        if(InpEnableTrend && CountEngineB(sym) < InpTrend_MaxPos) {
            int d1_struct = smc.GetMarketStructure(sym, InpTrend_D1);
            if(d1_struct == 1 && h4_struct == 1 && bid > ma && m15_struct == 1) {
                int nl = GetNextLayerB(sym);
                if(nl > 0) {
                    double lot = GetSafeLot(sym, true);
                    if(lot > 0) {
                        SMC_Zone bf[]; int bc = smc.GetActiveFVGs(sym, InpEntryTF, true, bf, 3);
                        if(bc > 0 && !IsTooClose(sym, bf[0].poc, MAGIC_TREND, InpTrend_MaxPos, InpTrend_MinDist_ATR)) {
                            trade.SetExpertMagicNumber(InpMagic + MAGIC_TREND + nl);
                            trade.BuyLimit(lot, bf[0].poc, sym, 0, 0, ORDER_TIME_GTC, 0, "B_TrendRun");
                        }
                    }
                }
            }
        }
        
        //=== ENGINE B+: Trend Runner Dip (Price < MA) ===
        if(InpEnableTrendPlus && CountEngineBPlus(sym) < InpTrendPlus_MaxPos) {
            int d1_struct = smc.GetMarketStructure(sym, InpTrend_D1);
            if(d1_struct == 1 && h4_struct == 1 && bid < ma && m15_struct == 1) {
                int nl = GetNextLayerBPlus(sym);
                if(nl > 0) {
                    double lot = GetSafeLot(sym, true);
                    if(lot > 0) {
                        SMC_Zone bf[]; int bc = smc.GetActiveFVGs(sym, InpEntryTF, true, bf, 3);
                        if(bc > 0 && !IsTooClose(sym, bf[0].poc, MAGIC_TREND_PLUS, InpTrendPlus_MaxPos, InpTrend_MinDist_ATR)) {
                            trade.SetExpertMagicNumber(InpMagic + MAGIC_TREND_PLUS + nl);
                            trade.BuyLimit(lot, bf[0].poc, sym, 0, 0, ORDER_TIME_GTC, 0, "B+_TrendDip");
                        }
                    }
                }
            }
        }
        
        //=== ENGINE C: Legacy Slots (BUY ONLY) ===
        if(InpEnableLegacy) {
            double leg_ma = GetMA(sym, InpLegacy_MA_TF, InpLegacy_MA_Period);
            if(leg_ma > 0 && bid < leg_ma) {
                // Find the currently active Legacy Slot (only one slot has risk at a time)
                int s = GetActiveLegacySlot(sym);
                
                int c_count = CountLegacySlot(sym, s);
                bool can_open = false;
                
                if(c_count == 0) {
                    can_open = true; // First entry for this slot
                } else if(c_count < InpLegacy_MaxPos) {
                    double lowest_p = GetLowestLegacySlotPrice(sym, s);
                    // Open next layer for this slot if price drops by DistPct
                    if(lowest_p > 0 && ((lowest_p - ask) / lowest_p * 100.0) >= InpLegacy_DistPct) {
                        can_open = true;
                    }
                }
                
                if(can_open) {
                    int nl = GetNextLayerLegacySlot(sym, s);
                    if(nl > 0) {
                        double lot = GetSafeLot(sym, true, true);
                        if(lot > 0) {
                            trade.SetExpertMagicNumber(InpMagic + MAGIC_LEGACY_BASE + (s * 10) + nl);
                            if(trade.Buy(lot, sym, ask, 0, 0, "C_Legacy" + IntegerToString(s))) {
                                // Successfully opened a lower trade for this slot
                                // Scratch all older (higher) trades IN THIS SLOT to break-even
                                UpdateLegacyExitsPerSlot(sym, s, ask);
                            }
                        }
                    }
                }
            }
        }
        
        //=== ENGINE D: Snowball (Breakout) ===
        datetime current_d_bar = iTime(sym, InpEngineD_TF, 0);
        if(current_d_bar != last_d_bar_time[i] && current_d_bar != 0) {
            last_d_bar_time[i] = current_d_bar;
            if(InpEnableSnowball && CountEngineD(sym) < InpEngineD_MaxPos) {
                // Check if current trend is Bullish (CHoCH Bullish happened)
                if(h4_struct == 1) {
                    // Check for fresh Bullish BOS (Breakout above previous swing high)
                    int bos_status = smc.CheckBreakoutDivergence(sym, InpEngineD_TF);
                    if(bos_status == 1 || bos_status == 2) { // 1 = Breakout with Div, 2 = Breakout NO Div (Strong)
                        if(!IsTooClose(sym, ask, MAGIC_SNOWBALL, InpEngineD_MaxPos, InpTrend_MinDist_ATR)) {
                            bool can_snowball = true;
                            for(int j=PositionsTotal()-1; j>=0; j--) {
                                ulong t = PositionGetTicket(j);
                                ulong m = PositionGetInteger(POSITION_MAGIC);
                                if(PositionGetString(POSITION_SYMBOL)==sym && IsMagicD(m)) {
                                    if(PositionGetDouble(POSITION_PROFIT) <= 0) { can_snowball = false; break; }
                                }
                            }
                            if(can_snowball) {
                                int nl = GetNextLayerD(sym);
                                if(nl > 0) {
                                    double lot = GetSafeLot(sym, true);
                                    if(bos_status == 2 && lot > 0) { // Strong Breakout (No Divergence) -> Multiply Lot!
                                        double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
                                        lot = MathFloor((lot * InpEngineD_LotMult) / step) * step;
                                    }
                                    if(lot > 0) {
                                        trade.SetExpertMagicNumber(InpMagic + MAGIC_SNOWBALL + nl);
                                        trade.Buy(lot, sym, ask, 0, 0, "D_Snowball");
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
    }
}

void CleanUpPendingOrders(string sym) {
    SMC_Zone b[]; int bc = smc.GetActiveFVGs(sym, InpEntryTF, true, b, MAX_LAYERS);
    SMC_Zone s[]; int sc = smc.GetActiveFVGs(sym, InpEntryTF, false, s, MAX_LAYERS);
    double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
    for(int j=OrdersTotal()-1; j>=0; j--) {
        ulong t=OrderGetTicket(j); ulong m=OrderGetInteger(ORDER_MAGIC);
        if(OrderGetString(ORDER_SYMBOL)==sym && IsMagicA(m)) {
            double p = OrderGetDouble(ORDER_PRICE_OPEN);
            bool v = false;
            for(int f=0; f<bc; f++) if(MathAbs(p-b[f].poc)<50*pt) v=true;
            for(int f=0; f<sc; f++) if(MathAbs(p-s[f].poc)<50*pt) v=true;
            if(!v) trade.OrderDelete(t);
        }
    }
}

//--- ENGINE A: Mean Reversion Management ---
void ManageEngineA(string sym, double ma, double bid, double ask) {
    double atr[]; int ah = iATR(sym, PERIOD_H1, 14);
    CopyBuffer(ah, 0, 0, 1, atr); IndicatorRelease(ah);
    double a = (ArraySize(atr)>0) ? atr[0] : 0;
    if(a == 0) return;
    
    double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
    double stoplevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * pt;
    if(stoplevel == 0) stoplevel = 10 * pt;
    
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong ticket = PositionGetTicket(i);
        ulong magic = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL) != sym || !IsMagicA(magic)) continue;
        
        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        long type = PositionGetInteger(POSITION_TYPE);
        double sl = PositionGetDouble(POSITION_SL);
        
        if(type == POSITION_TYPE_BUY && bid >= open + a * InpTP_ATR) {
            trade.PositionClose(ticket); continue;
        }
        if(type == POSITION_TYPE_SELL) {
            // Hard TP
            if(ask <= open - a * InpTP_ATR) {
                trade.PositionClose(ticket); continue;
            }
            
            // MA EXIT GUARD: SELL ONLY
            if(bid > ma) {
                trade.PositionClose(ticket); continue;
            }
            
            // TRAILING STOP FOR SELLS
            // If price drops below open by at least 1 ATR, start trailing at 0.5 ATR
            if(ask < open - a) {
                double trail = ask + a * 0.5; // Trail tightly behind current price
                if(sl == 0.0 || trail < sl) {
                    if(trail > ask + stoplevel + (10 * pt)) {
                        trade.PositionModify(ticket, trail, PositionGetDouble(POSITION_TP));
                    }
                }
            }
        }
    }
}

//--- ENGINES B & B+: Trend Runner Management ---
void ManageEnginesTrend(string sym, double bid, double ask) {
    double atr[]; int ah = iATR(sym, InpTrend_H4, 14);
    CopyBuffer(ah, 0, 0, 1, atr); IndicatorRelease(ah);
    double a = (ArraySize(atr)>0) ? atr[0] : 0;
    if(a == 0) return;
    
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong ticket = PositionGetTicket(i);
        ulong magic = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL) != sym || (!IsMagicB(magic) && !IsMagicBPlus(magic))) continue;
        
        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        long type = PositionGetInteger(POSITION_TYPE);
        
        // B and B+ are Buy Only and use Trailing Stop
        if(type == POSITION_TYPE_BUY) {
            if(bid > open + a * 1.0 && sl == 0.0) {
                trade.PositionModify(ticket, open, 0.0);
            }
            if(bid > open + a * 1.5) {
                double trail = bid - a * InpTrend_Trail_ATR;
                if(trail > sl || sl == 0.0) {
                    trade.PositionModify(ticket, trail, 0.0);
                }
            }
        }
    }
}

//--- ENGINE D: Snowball Management (Shared Trailing SL) ---
void ManageEngineD(string sym, double bid, double ask) {
    double atr[]; int ah = iATR(sym, InpTrend_H4, 14);
    CopyBuffer(ah, 0, 0, 1, atr); IndicatorRelease(ah);
    double a = (ArraySize(atr)>0) ? atr[0] : 0;
    if(a == 0) return;
    
    double highest_sl = 0;
    
    // First pass: find the highest shared SL among all Snowballs
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong ticket = PositionGetTicket(i);
        ulong magic = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL) != sym || !IsMagicD(magic)) continue;
        
        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        
        if(bid > open + a * 1.0) {
            if(open > highest_sl) highest_sl = open;
        }
        if(bid > open + a * 1.5) {
            double trail = bid - a * InpTrend_Trail_ATR;
            if(trail > highest_sl) highest_sl = trail;
        }
        if(sl > highest_sl) highest_sl = sl;
    }
    
    // Second pass: apply the highest SL to ALL Snowballs to group-close them
    if(highest_sl > 0) {
        for(int i=PositionsTotal()-1; i>=0; i--) {
            ulong ticket = PositionGetTicket(i);
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if(PositionGetString(POSITION_SYMBOL) != sym || !IsMagicD(magic)) continue;
            
            double sl = PositionGetDouble(POSITION_SL);
            if(highest_sl > sl || sl == 0.0) {
                if(highest_sl < bid) { // SL must be below current price
                    trade.PositionModify(ticket, highest_sl, 0.0);
                }
            }
        }
    }
}

void CloseAllTrades() {
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong t = PositionGetTicket(i);
        ulong m = PositionGetInteger(POSITION_MAGIC);
        if(IsOurMagic(m)) {
            trade.PositionClose(t);
        }
    }
    for(int i=OrdersTotal()-1; i>=0; i--) {
        ulong t = OrderGetTicket(i);
        ulong m = OrderGetInteger(ORDER_MAGIC);
        if(IsOurMagic(m)) {
            trade.OrderDelete(t);
        }
    }
}

void CheckPortGoal() {
    if(InpLegacy_ExitMode != EXIT_PORT_GOAL) return;
    
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double target = BaseBalance * (1.0 + (InpPort_GoalPct / 100.0));
    
    if(equity >= target) {
        Print("🎯 PORT GOAL REACHED! Equity: ", equity, " Target: ", target, " Closing ALL...");
        CloseAllTrades();
        BaseBalance = AccountInfoDouble(ACCOUNT_BALANCE); // Reset baseline for next cycle
    }
}

double GetInitialVolume(long pos_id) {
    if(HistorySelectByPosition(pos_id)) {
        int total = HistoryDealsTotal();
        for(int i=0; i<total; i++) {
            ulong deal_ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN) {
                return HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
            }
        }
    }
    return -1.0;
}

int GetStepLevel(double initial_vol, double current_vol, double base_pct) {
    if(initial_vol <= 0 || current_vol >= initial_vol) return 0;
    double closed_ratio = 1.0 - (current_vol / initial_vol);
    int level = 0;
    for(int n=1; n<=50; n++) {
        double expected_closed = (base_pct / 100.0) * (n * (n + 1)) / 2.0;
        if(closed_ratio >= expected_closed - 0.001) {
            level = n;
        } else {
            break;
        }
    }
    return level;
}

//--- ENGINE C: Legacy Management (Break-even Guard) ---
void ManageEngineC(string sym, double bid) {
    if(!InpEnableLegacy) return;
    
    double leg_ma = GetMA(sym, InpLegacy_MA_TF, InpLegacy_MA_Period);
    if(leg_ma <= 0) return;
    
    double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
    double stoplevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * pt;
    if(stoplevel == 0) stoplevel = 10 * pt;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double harvest_target = balance * (InpLegacy_HarvestPct / 100.0);
    double min_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
    double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
    
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong ticket = PositionGetTicket(i);
        ulong magic = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL) != sym || !IsMagicC(magic)) continue;
        
        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        double vol = PositionGetDouble(POSITION_VOLUME);
        double profit = PositionGetDouble(POSITION_PROFIT);
        
        // 1. Partial Profit Harvesting (Scale-Out)
        if(InpLegacy_ExitMode == EXIT_REBALANCE && InpLegacy_HarvestPct > 0 && profit >= harvest_target) {
            double close_vol = vol * (InpLegacy_HarvestClose / 100.0);
            close_vol = MathFloor(close_vol / step) * step;
            if(close_vol >= min_lot && (vol - close_vol) >= min_lot) {
                if(trade.PositionClosePartial(ticket, close_vol)) {
                    Print("Legacy Harvest: Closed ", close_vol, " lots on ticket ", ticket, " (Profit was ", profit, ")");
                    continue; // Skip BE logic this tick to avoid conflict
                }
            }
        }
        else if(InpLegacy_ExitMode == EXIT_STEP_CLOSE && InpLegacy_HarvestPct > 0) {
            long pos_id = PositionGetInteger(POSITION_IDENTIFIER);
            double initial_vol = GetInitialVolume(pos_id);
            if(initial_vol > 0) {
                double theoretical_profit = profit * (initial_vol / vol);
                int current_level = GetStepLevel(initial_vol, vol, InpLegacy_StepCloseBase);
                int next_level = current_level + 1;
                
                if(theoretical_profit >= harvest_target * next_level) {
                    double close_pct = InpLegacy_StepCloseBase * next_level;
                    double close_vol = initial_vol * (close_pct / 100.0);
                    close_vol = MathFloor(close_vol / step) * step;
                    
                    if(close_vol >= min_lot) {
                        if(close_vol >= vol || (vol - close_vol) < min_lot) {
                            trade.PositionClose(ticket);
                            Print("Legacy Step Close (Level ", next_level, "): Closed FULL remaining position.");
                            continue;
                        } else {
                            if(trade.PositionClosePartial(ticket, close_vol)) {
                                Print("Legacy Step Close (Level ", next_level, "): Closed ", close_vol, " lots (Profit target x", next_level, " reached)");
                                continue;
                            }
                        }
                    }
                }
            }
        }
        
        // 2. Break-Even logic when price crosses above EMA 200
        if(bid > leg_ma) {
            if(sl < open && bid > (open + stoplevel)) {
                trade.PositionModify(ticket, open, tp);
            }
        }
    }
}

void DrawDashboard() {
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    int active_slot = GetActiveLegacySlot(Symbol());
    
    string txt = "=== APEX v7.12 PENTA-ENGINE ===\n";
    txt += "Equity: $" + DoubleToString(equity, 2) + "\n";
    txt += "A:MeanRev | B/B+:Trend | C:Legacy | D:Snowball\n\n";
    
    txt += ">> BUDGET & RISK <<\n";
    txt += "Legacy Exit Mode   : " + EnumToString(InpLegacy_ExitMode) + "\n";
    if(InpLegacy_ExitMode == EXIT_PORT_GOAL) txt += "Port Goal Target   : $" + DoubleToString(BaseBalance * (1.0 + (InpPort_GoalPct/100.0)), 2) + "\n";
    txt += "Legacy Total Budget: " + DoubleToString(InpLegacy_SurvivalPct, 1) + "%\n";
    txt += "Active Legacy Slot : " + IntegerToString(active_slot) + " / " + IntegerToString(MAX_LEGACY_SLOTS) + "\n";
    txt += "Trend/MeanRev Risk : " + DoubleToString(InpSurvivalPct, 1) + "%\n\n";
    
    for(int i=0; i<sym_count; i++) {
        string sym = symbols[i];
        if(!SymbolInfoInteger(sym, SYMBOL_SELECT)) continue;
        double ma = GetMA(sym, InpMA_TF, InpMA_Period);
        double leg_ma = GetMA(sym, InpLegacy_MA_TF, InpLegacy_MA_Period);
        double bid = SymbolInfoDouble(sym, SYMBOL_BID);
        string zone = (bid<ma) ? "▲BUY ZONE" : "▼SELL ZONE";
        
        double buy_lots = GetBuyLots(sym);
        double sell_lots = GetSellLots(sym);
        double total_safe = GetTotalSafeLot(sym, InpSurvivalPct);
        double leg_safe = GetTotalSafeLot(sym, InpLegacy_SurvivalPct);
        
        string leg_status = "";
        int total_c = 0;
        for(int s=1; s<=MAX_LEGACY_SLOTS; s++) {
            int c = CountLegacySlot(sym, s);
            total_c += c;
            if(c > 0) leg_status += "[" + IntegerToString(s) + ":" + IntegerToString(c) + "] ";
        }
        
        txt += sym + " (Bid: " + DoubleToString(bid, SymbolInfoInteger(sym, SYMBOL_DIGITS)) + ")\n";
        txt += "---------------------------------\n";
        txt += "A) Mean Rev : " + IntegerToString(CountEngineA(sym)) + "/" + IntegerToString(InpMaxPositions) + "\n";
        txt += "B) Trend(>MA): " + IntegerToString(CountEngineB(sym)) + "/" + IntegerToString(InpTrend_MaxPos) + "\n";
        txt += "B+) Trend(<MA): " + IntegerToString(CountEngineBPlus(sym)) + "/" + IntegerToString(InpTrendPlus_MaxPos) + "\n";
        txt += "C) Legacy(<MA): " + IntegerToString(total_c) + " trades " + leg_status + "\n";
        txt += "D) Snowball: " + IntegerToString(CountEngineD(sym)) + "/" + IntegerToString(InpEngineD_MaxPos) + "\n";
        txt += "Normal Budget : " + DoubleToString(buy_lots,2) + " / " + DoubleToString(total_safe,2) + " max\n";
        txt += "Legacy Budget : " + DoubleToString(leg_safe,2) + " max\n";
        txt += "-------------------------\n";
    }
    
    if(!ObjectFind(0, "DB_BG")) ObjectCreate(0, "DB_BG", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "DB_BG", OBJPROP_XDISTANCE, 20);
    ObjectSetInteger(0, "DB_BG", OBJPROP_YDISTANCE, 20);
    ObjectSetString(0, "DB_BG", OBJPROP_TEXT, txt);
    ObjectSetInteger(0, "DB_BG", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, "DB_BG", OBJPROP_FONT, "Consolas");
    ObjectSetInteger(0, "DB_BG", OBJPROP_FONTSIZE, 10);
}
