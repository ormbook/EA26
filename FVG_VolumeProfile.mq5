//+------------------------------------------------------------------+
//|                                            FVG_VolumeProfile.mq5 |
//|                                Converted from PineScript LuxAlgo |
//+------------------------------------------------------------------+
#property copyright "AI Converted"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

// We set DRAW_NONE so the EA can read the buffers, but the visual chart uses objects
#property indicator_type1   DRAW_NONE
#property indicator_type2   DRAW_NONE
#property indicator_type3   DRAW_NONE
#property indicator_type4   DRAW_NONE
#property indicator_type5   DRAW_NONE
#property indicator_type6   DRAW_NONE

input group "FVG Volume Profile"
input ENUM_TIMEFRAMES InpVolTF = PERIOD_M5;     // Volume Data Timeframe
input int             InpBins = 15;             // Resolution Bins
input double          InpGapFilter = 0.5;       // Filter Gaps (StDev)
input color           InpBullColor = clrSeaGreen;
input color           InpBearColor = clrPurple;

double BufBullTop[];
double BufBullBot[];
double BufBullPOC[];
double BufBearTop[];
double BufBearBot[];
double BufBearPOC[];

struct FVG_Data {
    bool   isBull;
    double top;
    double bottom;
    double poc_price;
    datetime start_time;
    string obj_prefix;
    bool   active;
};
FVG_Data fvgs[];

int OnInit()
{
    SetIndexBuffer(0, BufBullTop, INDICATOR_DATA);
    SetIndexBuffer(1, BufBullBot, INDICATOR_DATA);
    SetIndexBuffer(2, BufBullPOC, INDICATOR_DATA);
    SetIndexBuffer(3, BufBearTop, INDICATOR_DATA);
    SetIndexBuffer(4, BufBearBot, INDICATOR_DATA);
    SetIndexBuffer(5, BufBearPOC, INDICATOR_DATA);
    
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "FVG_");
}

void CreateFVG(bool isBull, double bottom, double top, datetime start_time, datetime end_time) 
{
    MqlRates ltf[];
    int copied = CopyRates(_Symbol, InpVolTF, start_time, end_time - 1, ltf);
    
    double binVols[];
    ArrayResize(binVols, InpBins);
    ArrayInitialize(binVols, 0.0);
    double binSize = (top - bottom) / InpBins;
    
    if(copied > 0) {
        for(int j=0; j<copied; j++) {
            double cls = ltf[j].close;
            long vol = ltf[j].tick_volume;
            
            for(int k=0; k<InpBins; k++) {
                double binLower = bottom + k * binSize;
                double mid = binLower + binSize/2.0;
                if(MathAbs(cls - mid) <= binSize) {
                    binVols[k] += (double)vol;
                }
            }
        }
    }
    
    double maxVol = 0;
    double pocPrice = bottom + binSize/2.0;
    for(int k=0; k<InpBins; k++) {
        if(binVols[k] > maxVol) {
            maxVol = binVols[k];
            pocPrice = bottom + k * binSize + binSize/2.0;
        }
    }
    
    int idx = ArraySize(fvgs);
    ArrayResize(fvgs, idx+1);
    fvgs[idx].isBull = isBull;
    fvgs[idx].top = top;
    fvgs[idx].bottom = bottom;
    fvgs[idx].poc_price = pocPrice;
    fvgs[idx].start_time = start_time;
    fvgs[idx].obj_prefix = "FVG_" + TimeToString(start_time);
    fvgs[idx].active = true;
    
    string boxName = fvgs[idx].obj_prefix + "_BOX";
    ObjectCreate(0, boxName, OBJ_RECTANGLE, 0, start_time, top, start_time, bottom);
    ObjectSetInteger(0, boxName, OBJPROP_COLOR, isBull ? InpBullColor : InpBearColor);
    ObjectSetInteger(0, boxName, OBJPROP_FILL, true);
    ObjectSetInteger(0, boxName, OBJPROP_BACK, true);
    
    string pocName = fvgs[idx].obj_prefix + "_POC";
    ObjectCreate(0, pocName, OBJ_TREND, 0, start_time, pocPrice, start_time, pocPrice);
    ObjectSetInteger(0, pocName, OBJPROP_COLOR, isBull ? InpBullColor : InpBearColor);
    ObjectSetInteger(0, pocName, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, pocName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, pocName, OBJPROP_WIDTH, 2);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    int start = (prev_calculated == 0) ? 200 : prev_calculated - 1;
    if(start < 200) start = 200;
    
    // Limit history calculation to avoid freezing MT5
    if(prev_calculated == 0 && rates_total - start > 3000) {
        start = rates_total - 3000;
    }

    for(int i = start; i < rates_total; i++)
    {
        double sum_bull=0, sum_sq_bull=0;
        double sum_bear=0, sum_sq_bear=0;
        
        for(int k=0; k<200; k++) {
            double bg = low[i-k] - high[i-k-2];
            double brg = low[i-k-2] - high[i-k];
            sum_bull += bg;
            sum_sq_bull += bg*bg;
            sum_bear += brg;
            sum_sq_bear += brg*brg;
        }
        
        double mean_b = sum_bull / 200.0;
        double variance_b = (sum_sq_bull / 200.0) - (mean_b * mean_b);
        double stdev_bull = variance_b > 0 ? MathSqrt(variance_b) : 0;
        
        double mean_br = sum_bear / 200.0;
        double variance_br = (sum_sq_bear / 200.0) - (mean_br * mean_br);
        double stdev_bear = variance_br > 0 ? MathSqrt(variance_br) : 0;
        
        // FVG Detect
        double cur_bull_gap = low[i] - high[i-2];
        bool bull_cond = (low[i] > high[i-2]) && (high[i-1] > high[i-2]);
        if(bull_cond && stdev_bull > 0 && (cur_bull_gap / stdev_bull > InpGapFilter)) {
            CreateFVG(true, high[i-2], low[i], time[i-1], time[i]);
        }
        
        double cur_bear_gap = low[i-2] - high[i];
        bool bear_cond = (high[i] < low[i-2]) && (low[i-1] < low[i-2]);
        if(bear_cond && stdev_bear > 0 && (cur_bear_gap / stdev_bear > InpGapFilter)) {
            CreateFVG(false, high[i], low[i-2], time[i-1], time[i]);
        }
        
        // Invalidation Check
        for(int f=0; f<ArraySize(fvgs); f++) {
            if(!fvgs[f].active) continue;
            
            if(fvgs[f].isBull) {
                if(low[i] < fvgs[f].bottom) {
                    fvgs[f].active = false;
                    ObjectDelete(0, fvgs[f].obj_prefix + "_BOX");
                    ObjectDelete(0, fvgs[f].obj_prefix + "_POC");
                }
            } else {
                if(high[i] > fvgs[f].top) {
                    fvgs[f].active = false;
                    ObjectDelete(0, fvgs[f].obj_prefix + "_BOX");
                    ObjectDelete(0, fvgs[f].obj_prefix + "_POC");
                }
            }
        }
        
        // Update Buffers for EA (Most recent active FVG)
        BufBullTop[i] = EMPTY_VALUE;
        BufBullBot[i] = EMPTY_VALUE;
        BufBullPOC[i] = EMPTY_VALUE;
        BufBearTop[i] = EMPTY_VALUE;
        BufBearBot[i] = EMPTY_VALUE;
        BufBearPOC[i] = EMPTY_VALUE;
        
        for(int f=ArraySize(fvgs)-1; f>=0; f--) {
            if(fvgs[f].active) {
                if(fvgs[f].isBull && BufBullTop[i] == EMPTY_VALUE) {
                    BufBullTop[i] = fvgs[f].top;
                    BufBullBot[i] = fvgs[f].bottom;
                    BufBullPOC[i] = fvgs[f].poc_price;
                }
                if(!fvgs[f].isBull && BufBearTop[i] == EMPTY_VALUE) {
                    BufBearTop[i] = fvgs[f].top;
                    BufBearBot[i] = fvgs[f].bottom;
                    BufBearPOC[i] = fvgs[f].poc_price;
                }
            }
        }
    }
    
    // Extend active visual objects to current bar
    for(int f=0; f<ArraySize(fvgs); f++) {
        if(fvgs[f].active) {
            string boxName = fvgs[f].obj_prefix + "_BOX";
            ObjectSetInteger(0, boxName, OBJPROP_TIME, 1, time[rates_total-1]);
            
            string pocName = fvgs[f].obj_prefix + "_POC";
            ObjectSetInteger(0, pocName, OBJPROP_TIME, 1, time[rates_total-1]);
        }
    }
    
    return(rates_total);
}
