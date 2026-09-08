//+------------------------------------------------------------------+
//|                                                    Defines.mqh   |
//|                               Apex Quantum Multi-Confluence MQL5 |
//|                              Copyright 2026, Institutional Grade |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Apex Quantum Institutional"
#property link      "https://www.mql5.com"
#property strict

//--- Harmonic Pattern Enums
enum ENUM_HARMONIC_PATTERN
{
   PATTERN_NONE = 0,
   PATTERN_GARTLEY,
   PATTERN_BAT,
   PATTERN_ALT_BAT,
   PATTERN_CYPHER,
   PATTERN_SHARK,
   PATTERN_ALT_SHARK
};

//--- Signal Direction
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY,
   SIGNAL_SELL
};

//--- Market Structure Direction
enum ENUM_MARKET_TREND
{
   TREND_BULLISH = 1,
   TREND_BEARISH = -1,
   TREND_RANGING = 0
};

//--- EA Operational State Machine
enum ENUM_EA_STATE
{
   STATE_INITIALIZING = 0,
   STATE_SCANNING_H4,
   STATE_WAITING_ZONE,
   STATE_WAITING_PULLBACK,
   STATE_WAITING_M1_TRIGGER,
   STATE_ORDER_ACTIVE,
   STATE_RECOVERED_MANAGING,
   STATE_RISK_LOCKED,
   STATE_COOLDOWN,
   STATE_OUTSIDE_SESSION,
   STATE_PAUSED
};

//--- Point Structure for Swing Detection & Harmonics
struct SwingPoint
{
   datetime time;
   double   price;
   int      barIndex;
   bool     isHigh;
};

//--- Harmonic Pattern Result Struct
struct HarmonicPatternResult
{
   ENUM_HARMONIC_PATTERN patternType;
   ENUM_SIGNAL_TYPE      signal;
   SwingPoint            pointX;
   SwingPoint            pointA;
   SwingPoint            pointB;
   SwingPoint            pointC;
   SwingPoint            pointD;
   double                przLow;
   double                przHigh;
   double                targetTP1;
   double                targetTP2;
   double                targetTP3;
   double                stopLoss;
   double                qualityScore;
   bool                  isValid;
};

//--- Smart Money Concepts (SMC) Structs
struct OrderBlock
{
   ENUM_SIGNAL_TYPE signal;
   datetime         time;
   double           top;
   double           bottom;
   double           mitigationPrice;
   bool             isMitigated;
   int              barIndex;
};

struct FairValueGap
{
   ENUM_SIGNAL_TYPE signal;
   datetime         time;
   double           top;
   double           bottom;
   bool             isFilled;
};

struct LiquidityPool
{
   ENUM_SIGNAL_TYPE sweepDirection;
   double           levelPrice;
   datetime         sweepTime;
   bool             isSwept;
};

struct SMCAnalysisResult
{
   ENUM_MARKET_TREND marketTrend;
   bool              hasCHoCH;
   bool              hasBOS;
   bool              priceInOrderBlock;
   bool              priceInFVG;
   bool              hasLiquiditySweep;
   OrderBlock        activeOB;
   FairValueGap      activeFVG;
   LiquidityPool     activeSweep;
   double            qualityScore;
};

//--- Trend Channel & Speed Lines
struct ChannelResult
{
   bool   isValid;
   double upperLine;
   double middleLine;
   double lowerLine;
   double slope;
   bool   isNearSupport;
   bool   isNearResistance;
};

struct SpeedLinesResult
{
   bool   isValid;
   double line1_3;
   double line2_3;
   double lineMain;
   bool   isNearBounce;
};

//--- Technical Indicators Struct
struct IndicatorResult
{
   double rsiVal;
   bool   rsiOverbought;
   bool   rsiOversold;
   bool   rsiBullishDiv;
   bool   rsiBearishDiv;

   double stochMain;
   double stochSignal;
   double stochSlope;
   bool   stochBullishCross;
   bool   stochBearishCross;
   bool   stochOverbought;
   bool   stochOversold;

   double qualityScore;
};

//--- M1 Price Action Trigger Struct
struct PriceActionResult
{
   bool             hasTrigger;
   ENUM_SIGNAL_TYPE signal;
   string           patternName;
   double           triggerPrice;
   double           suggestedSL;
   double           confidence;
};

//--- Final Consensus Decision Struct (v2.0 + rrRatio)
struct ConsensusDecision
{
   ENUM_SIGNAL_TYPE signal;
   double           totalScore;
   double           smcScore;
   double           harmonicScore;
   double           channelScore;
   double           indicatorScore;
   double           paScore;
   double           rrRatio;      // Actual calculated Risk:Reward ratio

   double           entryZoneLow;
   double           entryZoneHigh;
   double           optimalEntry;
   double           stopLoss;
   double           tp1;
   double           tp2;
   double           tp3;

   string           reason;
   bool             isExecutable;
};

//--- Position Recovery Info Struct
struct ManagedPosition
{
   ulong            ticket;
   ENUM_SIGNAL_TYPE type;
   double           lots;
   double           openPrice;
   double           currentSL;
   double           currentTP;
   double           profit;
   double           pipsProfit;
   bool             isBreakEvenApplied;
   int              partialTPLevel;
   string           statusPlan;
};
