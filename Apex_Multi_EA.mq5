//+------------------------------------------------------------------+
//|                                             Apex_Multi_EA.mq5    |
//|            Penta-Engine: MeanRev, Trend, TrendDip, Legacy,       |
//|                          Snowball (v7.10)                        |
//+------------------------------------------------------------------+
#property copyright "AI Converted"
#property version   "9.00"

#include <Trade\Trade.mqh>
#include "Include\SMC_Engine.mqh"
#include "Include\Ichimoku_Engine.mqh"

#define MAX_LAYERS         10
#define MAGIC_TREND        100
#define MAGIC_TREND_PLUS   150
#define MAGIC_LEGACY_BASE  200
#define MAGIC_SNOWBALL     300
#define MAGIC_ICHIMOKU     400
#define MAX_LEGACY_SLOTS   20  // Support up to 20 slots

enum ENUM_LEGACY_EXIT_MODE {
    EXIT_HODL = 0,        // 1. HODL (Manual Close Only)
    EXIT_REBALANCE = 1,   // 2. Rebalancing (Scale-out specific trade)
    EXIT_PORT_GOAL = 2,   // 3. Goal Setting (Close All at Portfolio Target)
    EXIT_STEP_CLOSE = 3   // 4. Step Close (Progressive Scale-out)
};

enum ENUM_ENGINE_A_MODE {
    A_MODE_NORMAL = 0,         // 1. Normal (Current Logic)
    A_MODE_MOMENTUM = 1,       // 2. Momentum Filter
    A_MODE_DYNAMIC_TP = 2      // 3. Dynamic TP to EMA
};

enum ENUM_ENGINE_B_MODE {
    B_MODE_NORMAL = 0,         // 1. Normal (ATR Trail)
    B_MODE_SMART_TRAIL = 1,    // 2. Smart Structure Trail
    B_MODE_PYRAMIDING = 2      // 3. Pyramiding (Scale-In)
};

enum ENUM_ENGINE_C_MODE {
    C_MODE_NORMAL = 0,         // 1. Fixed % Distance
    C_MODE_EXPANDING = 1,      // 2. Expanding Grid (x1.5 Dist)
    C_MODE_SMART_SWEEP = 2     // 3. Smart Sweep (Wait for new low)
};

enum ENUM_ENGINE_D_MODE {
    D_MODE_NORMAL = 0,
    D_MODE_KILLZONE = 1,
    D_MODE_LIQUIDITY = 2
};


enum ENUM_MACRO_THEME {
    MACRO_BEARISH = -1,
    MACRO_RANGING = 0,
    MACRO_BULLISH = 1
};


enum ENUM_RISK_LEVEL {
    RISK_MANUAL = 0,
    RISK_1_SLEEP = 1,
    RISK_2_SAFE = 2,
    RISK_3_BALANCE = 3,
    RISK_4_ATTACK = 4,
    RISK_5_AGGRESSIVE = 5
};
double BaseBalance = 0; // Baseline for Port Goal

input group "=== General Settings ==="
input string InpVersion      = "v9.00 Master-Level"; // EA Version
input string InpSymbols      = "XAUUSD"; // Pairs to trade
input ulong user_InpMagic = 777888;   // Base Magic
input bool user_InpShowDash = true;     // Show Dashboard

input group "=== ⚡ Risk & Auto Configuration ==="
input ENUM_RISK_LEVEL user_InpRiskLevel = RISK_3_BALANCE; // System Risk Preset
input double user_InpAutoLot_Step_A = 1000; // Auto-Lot Step A ($/0.01 Lot) (0=Fixed)
input double user_InpFixedLot_A     = 0.01; // Fixed Lot A (If Step = 0)
input double user_InpAutoLot_Step_B = 500;  // Auto-Lot Step B ($/0.01 Lot)
input double user_InpFixedLot_B     = 0.02; // Fixed Lot B
input double user_InpAutoLot_Step_C = 2000; // Auto-Lot Step C ($/0.01 Lot)
input double user_InpFixedLot_C     = 0.01; // Fixed Lot C
input double user_InpAutoLot_Step_D = 500;  // Auto-Lot Step D ($/0.01 Lot)
input double user_InpFixedLot_D     = 0.02; // Fixed Lot D

input group "=== Engine A: Mean Reversion ==="
input bool user_InpEnableEngineA = true;        // Enable Engine A
input ENUM_ENGINE_A_MODE user_InpEngineA_Mode = A_MODE_MOMENTUM; // Engine A Strategy
input int user_InpMaxPositions = 10;       // Max positions for Engine A
input ENUM_TIMEFRAMES user_InpMA_TF = PERIOD_H4;   // MA Timeframe (Zone Filter)
input int user_InpMA_Period = 200;         // MA Period (EMA)
input ENUM_TIMEFRAMES user_InpEntryTF = PERIOD_M15;  // Entry TF for FVG
input double user_InpTP_ATR = 0.5;         // TP (ATR multiplier)
input double user_InpA_MinDist_ATR = 1.0;         // Min distance between A orders (ATR)
input bool user_InpCutOnCHoCH = true;        // Emergency H4 CHoCH cut (SELL ONLY)
input int user_InpEngineA_SellStartHour = 1;        // Sell Start Hour (Broker Time)
input int user_InpEngineA_SellEndHour = 13;       // Sell End Hour (Broker Time)

input group "=== Engine B & B+: Trend Shared Settings ==="
input ENUM_ENGINE_B_MODE user_InpEngineB_Mode = B_MODE_SMART_TRAIL; // Engine B Strategy
input ENUM_TIMEFRAMES user_InpTrend_D1 = PERIOD_D1;    // Trend TF1: Daily
input ENUM_TIMEFRAMES user_InpTrend_H4 = PERIOD_H4;    // Trend TF2: H4
input double user_InpTrend_Trail_ATR = 2.0;          // Trailing Stop (ATR multiplier)
input double user_InpTrend_MinDist_ATR = 1.0;          // Min distance between Trend orders (ATR)

input group "=== Engine B: Trend Runner (Price > MA) ==="
input bool user_InpEnableTrend = true;         // Enable Engine B
input int user_InpTrend_MaxPos = 3;            // Max Engine B positions
input int user_InpTrend_MinFVG_Pts = 50;           // Min FVG size (Points)

input group "=== Engine B+: Trend Runner Dip (Price < MA) ==="
input bool user_InpEnableTrendPlus = true;         // Enable Engine B+
input int user_InpTrendPlus_MaxPos = 3;            // Max Engine B+ positions

input group "=== Engine C: Legacy (Buy Only) ==="
input ENUM_ENGINE_C_MODE user_InpEngineC_Mode = C_MODE_SMART_SWEEP; // Engine C Strategy
input bool user_InpEnableLegacy = true;         // Enable Legacy Engine (Engine C)
input ENUM_TIMEFRAMES user_InpLegacy_MA_TF = PERIOD_D1; // Legacy MA Timeframe
input int user_InpLegacy_MA_Period = 200;          // Legacy MA Period (EMA)
input double user_InpLegacy_DistPct = 1.0;          // Base Distance to open new legacy (%)
input int user_InpLegacy_MaxPos = 5;            // Max grid positions PER SLOT for averaging
input double user_InpLegacy_LotMult = 1.5;          // Martingale Lot Multiplier (1.0 = Off)
input bool user_InpLegacy_GlobalCheck = true;         // Use Global Minimum Distance Check
input double user_InpLegacy_SurvivalPct = 30.0;         // Legacy Budget PER SLOT (%)
input ENUM_LEGACY_EXIT_MODE user_InpLegacy_ExitMode = EXIT_STEP_CLOSE; // Legacy Exit Strategy
input double user_InpLegacy_HarvestPct = 6.0;          // [Target] Profit Trigger (% of Balance)
input double user_InpLegacy_HarvestClose = 50.0;         // [Rebalance] % of Volume to close
input double user_InpLegacy_StepCloseBase = 5.0;        // [Step Close] Base % of Vol to close (e.g. 5,10,15)
input double user_InpPort_GoalPct = 50.0;         // [Goal Setting] Portfolio Target (%)

input group "=== Engine D: Snowball (Breakout) ==="
input ENUM_ENGINE_D_MODE user_InpEngineD_Mode = D_MODE_KILLZONE; // Engine D Strategy
input bool user_InpEnableSnowball = true;         // Enable Engine D
input ENUM_TIMEFRAMES user_InpEngineD_TF = PERIOD_H4;   // Breakout Timeframe (BOS)
input int user_InpEngineD_MaxPos = 5;            // Max Snowball positions
input double user_InpEngineD_LotMult = 2.0;          // Lot multiplier if NO Divergence
input int user_InpEngineD_KillzoneStart = 14;        // Killzone Start Hour (Broker Time)
input int user_InpEngineD_KillzoneEnd = 22;        // Killzone End Hour (Broker Time)


input group "=== Engine E: Ichimoku Macro Rider ==="
input bool user_InpEnableEngineE = true; // Enable Engine E
input ENUM_TIMEFRAMES user_InpEngineE_TF = PERIOD_H4; // Ichimoku Timeframe
input double user_InpAutoLot_Step_E = 200;  // Auto-Lot Step E ($/0.01 Lot)
input double user_InpFixedLot_E     = 0.05; // Fixed Lot E
input int user_InpEngineE_MaxPos = 1; // Max Engine E positions

input group "=== Risk ==="
input double user_InpSurvivalPct = 50.0;         // Survive X% crash (keep 50% equity)

//--- GLOBALS ---
ulong InpMagic;
bool InpShowDash;
ENUM_RISK_LEVEL InpRiskLevel;
double InpAutoLot_Step_A;
double InpFixedLot_A;
double InpAutoLot_Step_B;
double InpFixedLot_B;
double InpAutoLot_Step_C;
double InpFixedLot_C;
double InpAutoLot_Step_D;
double InpFixedLot_D;
bool InpEnableEngineA;
ENUM_ENGINE_A_MODE InpEngineA_Mode;
int InpMaxPositions;
ENUM_TIMEFRAMES InpMA_TF;
int InpMA_Period;
ENUM_TIMEFRAMES InpEntryTF;
double InpTP_ATR;
double InpA_MinDist_ATR;
bool InpCutOnCHoCH;
int InpEngineA_SellStartHour;
int InpEngineA_SellEndHour;
ENUM_ENGINE_B_MODE InpEngineB_Mode;
ENUM_TIMEFRAMES InpTrend_D1;
ENUM_TIMEFRAMES InpTrend_H4;
double InpTrend_Trail_ATR;
double InpTrend_MinDist_ATR;
bool InpEnableTrend;
int InpTrend_MaxPos;
int InpTrend_MinFVG_Pts;
bool InpEnableTrendPlus;
int InpTrendPlus_MaxPos;
ENUM_ENGINE_C_MODE InpEngineC_Mode;
bool InpEnableLegacy;
ENUM_TIMEFRAMES InpLegacy_MA_TF;
int InpLegacy_MA_Period;
double InpLegacy_DistPct;
int InpLegacy_MaxPos;
double InpLegacy_LotMult;
bool InpLegacy_GlobalCheck;
double InpLegacy_SurvivalPct;
ENUM_LEGACY_EXIT_MODE InpLegacy_ExitMode;
double InpLegacy_HarvestPct;
double InpLegacy_HarvestClose;
double InpLegacy_StepCloseBase;
double InpPort_GoalPct;
ENUM_ENGINE_D_MODE InpEngineD_Mode;
bool InpEnableSnowball;
ENUM_TIMEFRAMES InpEngineD_TF;
int InpEngineD_MaxPos;
double InpEngineD_LotMult;
int InpEngineD_KillzoneStart;
int InpEngineD_KillzoneEnd;
double InpSurvivalPct;

bool InpEnableEngineE;
ENUM_TIMEFRAMES InpEngineE_TF;
double InpAutoLot_Step_E;
double InpFixedLot_E;
int InpEngineE_MaxPos;
CIchimoku_Engine ichi;


//--- INIT ---
void ApplyRiskLevelSettings() {
    InpMagic = user_InpMagic;
    InpShowDash = user_InpShowDash;
    InpRiskLevel = user_InpRiskLevel;
    InpAutoLot_Step_A = user_InpAutoLot_Step_A;
    InpFixedLot_A = user_InpFixedLot_A;
    InpAutoLot_Step_B = user_InpAutoLot_Step_B;
    InpFixedLot_B = user_InpFixedLot_B;
    InpAutoLot_Step_C = user_InpAutoLot_Step_C;
    InpFixedLot_C = user_InpFixedLot_C;
    InpAutoLot_Step_D = user_InpAutoLot_Step_D;
    InpFixedLot_D = user_InpFixedLot_D;
    InpEnableEngineA = user_InpEnableEngineA;
    InpEngineA_Mode = user_InpEngineA_Mode;
    InpMaxPositions = user_InpMaxPositions;
    InpMA_TF = user_InpMA_TF;
    InpMA_Period = user_InpMA_Period;
    InpEntryTF = user_InpEntryTF;
    InpTP_ATR = user_InpTP_ATR;
    InpA_MinDist_ATR = user_InpA_MinDist_ATR;
    InpCutOnCHoCH = user_InpCutOnCHoCH;
    InpEngineA_SellStartHour = user_InpEngineA_SellStartHour;
    InpEngineA_SellEndHour = user_InpEngineA_SellEndHour;
    InpEngineB_Mode = user_InpEngineB_Mode;
    InpTrend_D1 = user_InpTrend_D1;
    InpTrend_H4 = user_InpTrend_H4;
    InpTrend_Trail_ATR = user_InpTrend_Trail_ATR;
    InpTrend_MinDist_ATR = user_InpTrend_MinDist_ATR;
    InpEnableTrend = user_InpEnableTrend;
    InpTrend_MaxPos = user_InpTrend_MaxPos;
    InpTrend_MinFVG_Pts = user_InpTrend_MinFVG_Pts;
    InpEnableTrendPlus = user_InpEnableTrendPlus;
    InpTrendPlus_MaxPos = user_InpTrendPlus_MaxPos;
    InpEngineC_Mode = user_InpEngineC_Mode;
    InpEnableLegacy = user_InpEnableLegacy;
    InpLegacy_MA_TF = user_InpLegacy_MA_TF;
    InpLegacy_MA_Period = user_InpLegacy_MA_Period;
    InpLegacy_DistPct = user_InpLegacy_DistPct;
    InpLegacy_MaxPos = user_InpLegacy_MaxPos;
    InpLegacy_LotMult = user_InpLegacy_LotMult;
    InpLegacy_GlobalCheck = user_InpLegacy_GlobalCheck;
    InpLegacy_SurvivalPct = user_InpLegacy_SurvivalPct;
    InpLegacy_ExitMode = user_InpLegacy_ExitMode;
    InpLegacy_HarvestPct = user_InpLegacy_HarvestPct;
    InpLegacy_HarvestClose = user_InpLegacy_HarvestClose;
    InpLegacy_StepCloseBase = user_InpLegacy_StepCloseBase;
    InpPort_GoalPct = user_InpPort_GoalPct;
    InpEngineD_Mode = user_InpEngineD_Mode;
    InpEnableSnowball = user_InpEnableSnowball;
    InpEngineD_TF = user_InpEngineD_TF;
    InpEngineD_MaxPos = user_InpEngineD_MaxPos;
    InpEngineD_LotMult = user_InpEngineD_LotMult;
    InpEngineD_KillzoneStart = user_InpEngineD_KillzoneStart;
    InpEngineD_KillzoneEnd = user_InpEngineD_KillzoneEnd;
    InpSurvivalPct = user_InpSurvivalPct;

    InpEnableEngineE = user_InpEnableEngineE;
    InpEngineE_TF = user_InpEngineE_TF;
    InpAutoLot_Step_E = user_InpAutoLot_Step_E;
    InpFixedLot_E = user_InpFixedLot_E;
    InpEngineE_MaxPos = user_InpEngineE_MaxPos;


    if (user_InpRiskLevel != RISK_MANUAL) {
        // Level 5: Aggressive
        if (user_InpRiskLevel == RISK_5_AGGRESSIVE) {
            InpEngineA_Mode = A_MODE_NORMAL;
            InpEngineB_Mode = B_MODE_SMART_TRAIL;
            InpEngineC_Mode = C_MODE_SMART_SWEEP;
            InpLegacy_ExitMode = EXIT_STEP_CLOSE;
            InpEngineD_Mode = D_MODE_KILLZONE;
            InpLegacy_LotMult = 1.5;
        }
        // Level 4: Attacking
        else if (user_InpRiskLevel == RISK_4_ATTACK) {
            InpEngineA_Mode = A_MODE_MOMENTUM;
            InpEngineB_Mode = B_MODE_SMART_TRAIL;
            InpEngineC_Mode = C_MODE_EXPANDING;
            InpLegacy_ExitMode = EXIT_STEP_CLOSE;
            InpEngineD_Mode = D_MODE_KILLZONE;
        }
        // Level 3: Balance
        else if (user_InpRiskLevel == RISK_3_BALANCE) {
            InpEngineA_Mode = A_MODE_MOMENTUM;
            InpEngineB_Mode = B_MODE_PYRAMIDING;
            InpEngineC_Mode = C_MODE_SMART_SWEEP;
            InpLegacy_ExitMode = EXIT_STEP_CLOSE;
            InpEngineD_Mode = D_MODE_KILLZONE;
        }
        // Level 2: Safe
        else if (user_InpRiskLevel == RISK_2_SAFE) {
            InpEngineA_Mode = A_MODE_MOMENTUM;
            InpEngineB_Mode = B_MODE_PYRAMIDING;
            InpEngineC_Mode = C_MODE_EXPANDING;
            InpLegacy_ExitMode = EXIT_PORT_GOAL;
            InpEngineD_Mode = D_MODE_LIQUIDITY;
        }
        // Level 1: Sleep
        else if (user_InpRiskLevel == RISK_1_SLEEP) {
            InpEngineA_Mode = A_MODE_MOMENTUM;
            InpEngineB_Mode = B_MODE_PYRAMIDING;
            InpEngineC_Mode = C_MODE_SMART_SWEEP;
            InpLegacy_ExitMode = EXIT_PORT_GOAL;
            InpEngineD_Mode = D_MODE_LIQUIDITY;
            InpLegacy_GlobalCheck = true;
            InpTrend_MaxPos = 2;
        }
    }
}



CTrade trade;
CSMC_Engine smc;
string symbols[];
int sym_count = 0;
datetime last_bar_time[20];
datetime last_d_bar_time[20];
int prev_m15_struct[20];

int OnInit()
{
    ApplyRiskLevelSettings();
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
    if(!ichi.Init(symbols[0], InpEngineE_TF)) Print("Ichimoku Init Failed");

    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); ObjectsDeleteAll(0, "DB_"); }

//--- Magic Number helpers ---
bool IsMagicA(ulong m) { return (m >= InpMagic+1 && m <= InpMagic+MAX_LAYERS); }
bool IsMagicB(ulong m) { return (m >= InpMagic+MAGIC_TREND+1 && m <= InpMagic+MAGIC_TREND+InpTrend_MaxPos); }
bool IsMagicBPlus(ulong m) { return (m >= InpMagic+MAGIC_TREND_PLUS+1 && m <= InpMagic+MAGIC_TREND_PLUS+InpTrendPlus_MaxPos); }
bool IsMagicC(ulong m) { return (m > InpMagic + MAGIC_LEGACY_BASE && m <= InpMagic + MAGIC_LEGACY_BASE + (MAX_LEGACY_SLOTS * 10)); }
bool IsMagicD(ulong m) { return (m >= InpMagic+MAGIC_SNOWBALL+1 && m <= InpMagic+MAGIC_SNOWBALL+InpEngineD_MaxPos); }
bool IsMagicE(ulong m) { return (m >= InpMagic+MAGIC_ICHIMOKU+1 && m <= InpMagic+MAGIC_ICHIMOKU+InpEngineE_MaxPos); }
bool IsOurMagic(ulong m) { return IsMagicA(m) || IsMagicB(m) || IsMagicBPlus(m) || IsMagicC(m) || IsMagicD(m) || IsMagicE(m); }


ENUM_MACRO_THEME GetMacroTheme(string sym) {
    double w1_high = smc.GetLastSwingHigh(sym, PERIOD_W1, 3);
    double w1_low = smc.GetLastSwingLow(sym, PERIOD_W1, 3);
    double current = SymbolInfoDouble(sym, SYMBOL_BID);
    if(w1_high > 0 && current > w1_high) return MACRO_BULLISH;
    if(w1_low > 0 && current < w1_low) return MACRO_BEARISH;
    return MACRO_RANGING;
}

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



double GetEngineBFloatingProfit(string sym) {
    double pnl = 0;
    for(int i=0; i<PositionsTotal(); i++) {
        ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && (IsMagicB(m) || IsMagicBPlus(m))) {
            pnl += PositionGetDouble(POSITION_PROFIT);
        }
    }
    return pnl;
}

double GetLowestLegacySlotPrice(string sym, int slot) {
    double min_p = -1;
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong t = PositionGetTicket(j);
        ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && GetLegacySlot(m) == slot) {
            double p = PositionGetDouble(POSITION_PRICE_OPEN);
            if(min_p < 0 || p < min_p) min_p = p;
        }
    }
    return min_p;
}

double GetLowestLegacySlotLot(string sym, int slot) {
    double min_p = -1;
    double min_lot = 0;
    for(int j=PositionsTotal()-1; j>=0; j--) {
        ulong t = PositionGetTicket(j);
        ulong m = PositionGetInteger(POSITION_MAGIC);
        if(PositionGetString(POSITION_SYMBOL)==sym && GetLegacySlot(m) == slot) {
            double p = PositionGetDouble(POSITION_PRICE_OPEN);
            if(min_p < 0 || p < min_p) {
                min_p = p;
                min_lot = PositionGetDouble(POSITION_VOLUME);
            }
        }
    }
    return min_lot;
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

double GetADX(string sym, ENUM_TIMEFRAMES tf, int period) {
    int h = iADX(sym, tf, period);
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

ulong last_deal_ticket = 0;
double pnl_A=0, pnl_B=0, pnl_C=0, pnl_D=0;

void UpdatePnL() {
    HistorySelect(0, TimeCurrent());
    int total = HistoryDealsTotal();
    ulong highest_ticket = last_deal_ticket;
    for(int i=total-1; i>=0; i--) {
        ulong t = HistoryDealGetTicket(i);
        if(t == last_deal_ticket) break; // Reached known deals
        
        ulong magic = HistoryDealGetInteger(t, DEAL_MAGIC);
        double profit = HistoryDealGetDouble(t, DEAL_PROFIT);
        double swap = HistoryDealGetDouble(t, DEAL_SWAP);
        double comm = HistoryDealGetDouble(t, DEAL_COMMISSION);
        double net = profit + swap + comm;
        
        if(IsMagicA(magic)) pnl_A += net;
        else if(IsMagicB(magic) || IsMagicBPlus(magic)) pnl_B += net;
        else if(IsMagicC(magic)) pnl_C += net;
        else if(IsMagicD(magic)) pnl_D += net;
        
        if(i == total-1) highest_ticket = t;
    }
    last_deal_ticket = highest_ticket;
}


double GetDynamicLot(double step, double fixedLot, string sym) {
    if(step <= 0) return fixedLot;
    double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    double lot = (bal / step) * 0.01;
    
    double min_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
    
    lot = MathFloor(lot / lot_step) * lot_step;
    if(lot < min_lot) lot = min_lot;
    if(lot > max_lot) lot = max_lot;
    return lot;
}

void OnTimer()
{
    UpdatePnL();
    CheckPortGoal();
    
    bool isFastTest = (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));
    if(InpShowDash && !isFastTest) DrawDashboard();
    
    for(int i=0; i<sym_count; i++) {
        string sym = symbols[i];
        ENUM_MACRO_THEME macroTheme = GetMacroTheme(sym);

        //=== GLOBAL EQUITY PROTECTOR (ANTI-PORT แตก) ===
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double max_allowed_dd = InpSurvivalPct / 100.0;
        if(balance > 0 && (balance - equity) / balance > max_allowed_dd) {
            Print("EMERGENCY: Max Drawdown Reached! Closing all positions for ", sym);
            for(int j=PositionsTotal()-1; j>=0; j--) {
                ulong m = PositionGetInteger(POSITION_MAGIC);
                if(PositionGetString(POSITION_SYMBOL)==sym && IsOurMagic(m)) {
                    trade.PositionClose(PositionGetTicket(j));
                }
            }
            continue; // Skip opening new trades for this symbol
        }

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
        
        // Upgrade 1: Momentum Filter (A_MODE_MOMENTUM)
        if(fresh_signal && InpEngineA_Mode == A_MODE_MOMENTUM) {
            double adx = GetADX(sym, InpEntryTF, 14);
            if(adx > 30.0) {
                fresh_signal = false; // Trend is too strong
            }
        }
        
        if(fresh_signal && CountEngineA(sym) < InpMaxPositions) {
            int nl = GetNextLayerA(sym);
            if(nl > 0) {
                double lot = GetSafeLot(sym, (zone==1));
                if(lot > 0) {
                    if(zone == 1 && macroTheme != MACRO_BEARISH) {
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
                    bool can_pyramid = true;
                    if(InpEngineB_Mode == B_MODE_PYRAMIDING && CountEngineB(sym) > 0) {
                        if(GetEngineBFloatingProfit(sym) <= 0) can_pyramid = false;
                    }
                    
                    if(can_pyramid) {
                        double lot = GetDynamicLot(InpAutoLot_Step_B, InpFixedLot_B, sym);
                        if(InpEngineB_Mode == B_MODE_PYRAMIDING && nl > 1) {
                            lot = lot * (1.0 / nl); // Reduce lot size for higher layers (e.g. 1/2, 1/3)
                            double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
                            lot = MathFloor(lot / step) * step;
                        }
                        
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
        }
        
        //=== ENGINE B+: Trend Runner Dip (Price < MA) ===
        if(InpEnableTrendPlus && CountEngineBPlus(sym) < InpTrendPlus_MaxPos) {
            int d1_struct = smc.GetMarketStructure(sym, InpTrend_D1);
            if(d1_struct == 1 && h4_struct == 1 && bid < ma && m15_struct == 1) {
                int nl = GetNextLayerBPlus(sym);
                if(nl > 0) {
                    bool can_pyramid = true;
                    if(InpEngineB_Mode == B_MODE_PYRAMIDING && CountEngineBPlus(sym) > 0) {
                        if(GetEngineBFloatingProfit(sym) <= 0) can_pyramid = false;
                    }
                    
                    if(can_pyramid) {
                        double lot = GetDynamicLot(InpAutoLot_Step_B, InpFixedLot_B, sym);
                        if(InpEngineB_Mode == B_MODE_PYRAMIDING && nl > 1) {
                            lot = lot * (1.0 / nl);
                            double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
                            lot = MathFloor(lot / step) * step;
                        }
                        
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
        }
        
        //=== ENGINE C: Legacy Slots (BUY ONLY) ===
        if(InpEnableLegacy && macroTheme != MACRO_BEARISH) {
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
                    if(lowest_p > 0) {
                        double required_dist = InpLegacy_DistPct;
                        if(InpEngineC_Mode == C_MODE_EXPANDING) {
                            required_dist = InpLegacy_DistPct * MathPow(1.5, c_count); // 1.5, 2.25, 3.375...
                        }
                        
                        bool dist_met = (((lowest_p - ask) / lowest_p * 100.0) >= required_dist);
                        if(dist_met) {
                            if(InpEngineC_Mode == C_MODE_SMART_SWEEP) {
                                if(smc.CheckBullishSweep(sym, PERIOD_M15, 10)) can_open = true;
                            } else {
                                can_open = true;
                            }
                        }
                    }
                }
                
                // Idea 3: Global Minimum Distance Check (prevent clustering across engines)
                if(can_open && InpLegacy_GlobalCheck && c_count > 0) {
                    double atr[]; int ah = iATR(sym, PERIOD_D1, 14);
                    CopyBuffer(ah, 0, 0, 1, atr); IndicatorRelease(ah);
                    double a = (ArraySize(atr)>0) ? atr[0] : 0;
                    if(a > 0) {
                        for(int j=0; j<PositionsTotal(); j++) {
                            if(PositionGetString(POSITION_SYMBOL) != sym) continue;
                            double open = PositionGetDouble(POSITION_PRICE_OPEN);
                            double sl = PositionGetDouble(POSITION_SL);
                            long type = PositionGetInteger(POSITION_TYPE);
                            bool is_unprotected = false;
                            if(type == POSITION_TYPE_BUY && (sl == 0.0 || sl < open)) is_unprotected = true;
                            if(type == POSITION_TYPE_SELL && (sl == 0.0 || sl > open)) is_unprotected = true;
                            
                            if(is_unprotected) {
                                if(MathAbs(ask - open) < a * 0.5) { can_open = false; break; }
                            }
                        }
                    }
                }
                
                if(can_open) {
                    int nl = GetNextLayerLegacySlot(sym, s);
                    if(nl > 0) {
                        double lot = GetDynamicLot(InpAutoLot_Step_C, InpFixedLot_C, sym);
                        if(c_count > 0 && InpLegacy_LotMult > 1.0) {
                            double last_lot = GetLowestLegacySlotLot(sym, s);
                            if(last_lot > 0) {
                                lot = last_lot * InpLegacy_LotMult;
                                double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
                                lot = MathFloor(lot / step) * step;
                            }
                        }
                        
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
                // Option 2: Killzone Filter (D_MODE_KILLZONE)
                bool killzone_ok = true;
                if(InpEngineD_Mode == D_MODE_KILLZONE) {
                    MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
                    if(dt.hour < InpEngineD_KillzoneStart || dt.hour > InpEngineD_KillzoneEnd) killzone_ok = false;
                }
                
                if(killzone_ok && h4_struct == 1) {
                    // Check for fresh Bullish BOS (Breakout above previous swing high)
                    int bos_status = smc.CheckBreakoutDivergence(sym, InpEngineD_TF);
                    
                    // Option 3: Liquidity Sweep Filter (D_MODE_LIQUIDITY)
                    bool liq_ok = true;
                    if(InpEngineD_Mode == D_MODE_LIQUIDITY) {
                        liq_ok = smc.CheckBullishSweep(sym, InpEngineD_TF, 10);
                    }
                    
                    if(liq_ok && (bos_status == 1 || bos_status == 2)) { // 1 = Breakout with Div, 2 = Breakout NO Div (Strong)
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
                                    double lot = GetDynamicLot(InpAutoLot_Step_D, InpFixedLot_D, sym);
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
        
        bool should_close = false;
        
        // Upgrade 2: Dynamic TP to EMA (A_MODE_DYNAMIC_TP)
        if(InpEngineA_Mode == A_MODE_DYNAMIC_TP) {
            if(type == POSITION_TYPE_BUY && bid >= ma) should_close = true;
            if(type == POSITION_TYPE_SELL && ask <= ma) should_close = true;
        } else {
            // Normal ATR TP
            if(type == POSITION_TYPE_BUY && bid >= open + a * InpTP_ATR) should_close = true;
            if(type == POSITION_TYPE_SELL && ask <= open - a * InpTP_ATR) should_close = true;
        }
        
        if(should_close) {
            trade.PositionClose(ticket); 
            continue;
        }
        
        if(type == POSITION_TYPE_SELL) {
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
            // Upgrade 1: Smart Structure Trail (B_MODE_SMART_TRAIL)
            if(InpEngineB_Mode == B_MODE_SMART_TRAIL) {
                if(bid > open + a * 1.5) {
                    double swing_low = smc.GetLastSwingLow(sym, InpTrend_H4, 3);
                    if(swing_low > 0 && swing_low > open) {
                        double smart_trail = swing_low - (a * 0.2); // Trail slightly below the swing low
                        if(smart_trail > sl || sl == 0.0) {
                            trade.PositionModify(ticket, smart_trail, 0.0);
                        }
                    } else if(sl == 0.0 && bid > open + a * 1.0) {
                        // Fallback break-even if no swing low found above open yet
                        trade.PositionModify(ticket, open, 0.0);
                    }
                }
            } else {
                // Normal ATR Trailing
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
    
    string txt = "=== APEX v8.00 PENTA-ENGINE ===\n";
    txt += "Equity: $" + DoubleToString(equity, 2) + "\n";
    txt += "A:MeanRev | B/B+:Trend | C:Legacy | D:Snowball\n\n";
    
    txt += ">> BUDGET & RISK <<\n";
    txt += "Legacy Exit Mode   : " + EnumToString(InpLegacy_ExitMode) + "\n";
    if(InpLegacy_ExitMode == EXIT_PORT_GOAL) txt += "Port Goal Target   : $" + DoubleToString(BaseBalance * (1.0 + (InpPort_GoalPct/100.0)), 2) + "\n";
    txt += "Legacy Total Budget: " + DoubleToString(InpLegacy_SurvivalPct, 1) + "%\n";
    txt += "Active Legacy Slot : " + IntegerToString(active_slot) + " / " + IntegerToString(MAX_LEGACY_SLOTS) + "\n";
    txt += "Trend/MeanRev Risk : " + DoubleToString(InpSurvivalPct, 1) + "%\n\n";

    txt += ">> PROFIT BY ENGINE (REALTIME) <<\n";
    txt += "Engine A (Mean Rev): $" + DoubleToString(pnl_A, 2) + "\n";
    txt += "Engine B (Trend)   : $" + DoubleToString(pnl_B, 2) + "\n";
    txt += "Engine C (Legacy)  : $" + DoubleToString(pnl_C, 2) + "\n";
    txt += "Engine D (Snowball): $" + DoubleToString(pnl_D, 2) + "\n\n";
    
    for(int i=0; i<sym_count; i++) {
        string sym = symbols[i];
        ENUM_MACRO_THEME macroTheme = GetMacroTheme(sym);

        //=== GLOBAL EQUITY PROTECTOR (ANTI-PORT แตก) ===
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double max_allowed_dd = InpSurvivalPct / 100.0;
        if(balance > 0 && (balance - equity) / balance > max_allowed_dd) {
            Print("EMERGENCY: Max Drawdown Reached! Closing all positions for ", sym);
            for(int j=PositionsTotal()-1; j>=0; j--) {
                ulong m = PositionGetInteger(POSITION_MAGIC);
                if(PositionGetString(POSITION_SYMBOL)==sym && IsOurMagic(m)) {
                    trade.PositionClose(PositionGetTicket(j));
                }
            }
            continue; // Skip opening new trades for this symbol
        }

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









