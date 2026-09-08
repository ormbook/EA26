//+------------------------------------------------------------------+
//|                                              MarketStructure.mq5 |
//|                                Converted from PineScript LuxAlgo |
//+------------------------------------------------------------------+
#property copyright "AI Converted"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   2

#property indicator_label1  "Support"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSeaGreen
#property indicator_style1  STYLE_DASH

#property indicator_label2  "Resistance"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_DASH

input int InpLength = 5; // Fractal Length

double BufSupport[];
double BufResistance[];
double BufBullSignal[]; // 1.0 = BOS, 2.0 = ChoCH
double BufBearSignal[]; // 1.0 = BOS, 2.0 = ChoCH
double BufState[];      // 1 = Bullish, -1 = Bearish

int p;
double upper_value = 0;
int upper_loc = -1;
bool upper_iscrossed = true;

double lower_value = 0;
int lower_loc = -1;
bool lower_iscrossed = true;

double current_support = 0;
double current_resistance = 0;

int OnInit()
{
    SetIndexBuffer(0, BufSupport, INDICATOR_DATA);
    SetIndexBuffer(1, BufResistance, INDICATOR_DATA);
    SetIndexBuffer(2, BufBullSignal, INDICATOR_CALCULATIONS);
    SetIndexBuffer(3, BufBearSignal, INDICATOR_CALCULATIONS);
    SetIndexBuffer(4, BufState, INDICATOR_CALCULATIONS);

    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    p = InpLength / 2;
    if(p < 1) p = 1;

    return(INIT_SUCCEEDED);
}

int CalculateDH(const double &high[], int index, int count) {
    int sum = 0;
    for(int k=0; k<count; k++) {
        if(index-k-1 < 0) return 0;
        if(high[index-k] > high[index-k-1]) sum += 1;
        else if(high[index-k] < high[index-k-1]) sum -= 1;
    }
    return sum;
}

int CalculateDL(const double &low[], int index, int count) {
    int sum = 0;
    for(int k=0; k<count; k++) {
        if(index-k-1 < 0) return 0;
        if(low[index-k] > low[index-k-1]) sum += 1;
        else if(low[index-k] < low[index-k-1]) sum -= 1;
    }
    return sum;
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
    int start = (prev_calculated == 0) ? InpLength : prev_calculated - 1;

    for(int i = start; i < rates_total; i++)
    {
        BufBullSignal[i] = 0;
        BufBearSignal[i] = 0;

        if(i > 0) {
            BufSupport[i] = BufSupport[i-1];
            BufResistance[i] = BufResistance[i-1];
            BufState[i] = BufState[i-1];
        } else {
            BufSupport[i] = EMPTY_VALUE;
            BufResistance[i] = EMPTY_VALUE;
            BufState[i] = 0;
        }

        // Calculate Fractal Logic
        int dh = CalculateDH(high, i, p);
        int dh_p = CalculateDH(high, i-p, p);

        int dl = CalculateDL(low, i, p);
        int dl_p = CalculateDL(low, i-p, p);

        // Bullish Fractal
        if(dh == -p && dh_p == p) {
            double maxH = high[i];
            for(int k=1; k<InpLength; k++) {
                if(i-k >= 0 && high[i-k] > maxH) maxH = high[i-k];
            }
            if(high[i-p] == maxH) {
                upper_value = high[i-p];
                upper_loc = i-p;
                upper_iscrossed = false;
            }
        }

        // Bearish Fractal
        if(dl == p && dl_p == -p) {
            double minL = low[i];
            for(int k=1; k<InpLength; k++) {
                if(i-k >= 0 && low[i-k] < minL) minL = low[i-k];
            }
            if(low[i-p] == minL) {
                lower_value = low[i-p];
                lower_loc = i-p;
                lower_iscrossed = false;
            }
        }

        // Breakout Logic (Bullish)
        if(!upper_iscrossed && close[i-1] <= upper_value && close[i] > upper_value) {
            upper_iscrossed = true;
            int os_prev = (int)BufState[i-1];
            BufState[i] = 1;

            BufBullSignal[i] = (os_prev == -1) ? 2.0 : 1.0; // 2=ChoCH, 1=BOS

            double minS = low[i];
            for(int k=upper_loc; k<=i; k++) {
                if(k >= 0 && low[k] < minS) minS = low[k];
            }
            current_support = minS;
            BufSupport[i] = current_support;

            // Visuals
            if (prev_calculated == 0 || i == rates_total - 1) {
                string lineName = "MS_BOS_Line_" + TimeToString(time[i]);
                ObjectCreate(0, lineName, OBJ_TREND, 0, time[upper_loc], upper_value, time[i], upper_value);
                ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrSeaGreen);
                ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
                
                string lblName = "MS_BOS_Lbl_" + TimeToString(time[i]);
                ObjectCreate(0, lblName, OBJ_TEXT, 0, time[i], upper_value);
                ObjectSetString(0, lblName, OBJPROP_TEXT, (os_prev == -1) ? " ChoCH" : " BOS");
                ObjectSetInteger(0, lblName, OBJPROP_COLOR, clrSeaGreen);
                ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
            }
        }

        // Breakout Logic (Bearish)
        if(!lower_iscrossed && close[i-1] >= lower_value && close[i] < lower_value) {
            lower_iscrossed = true;
            int os_prev = (int)BufState[i-1];
            BufState[i] = -1;

            BufBearSignal[i] = (os_prev == 1) ? 2.0 : 1.0;

            double maxR = high[i];
            for(int k=lower_loc; k<=i; k++) {
                if(k >= 0 && high[k] > maxR) maxR = high[k];
            }
            current_resistance = maxR;
            BufResistance[i] = current_resistance;

            // Visuals
            if (prev_calculated == 0 || i == rates_total - 1) {
                string lineName = "MS_BOS_Line_" + TimeToString(time[i]);
                ObjectCreate(0, lineName, OBJ_TREND, 0, time[lower_loc], lower_value, time[i], lower_value);
                ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrRed);
                ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
                
                string lblName = "MS_BOS_Lbl_" + TimeToString(time[i]);
                ObjectCreate(0, lblName, OBJ_TEXT, 0, time[i], lower_value);
                ObjectSetString(0, lblName, OBJPROP_TEXT, (os_prev == 1) ? " ChoCH" : " BOS");
                ObjectSetInteger(0, lblName, OBJPROP_COLOR, clrRed);
                ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            }
        }
        
        // Clear broken support/resistance visually
        if(BufSupport[i] != EMPTY_VALUE && close[i] < BufSupport[i]) {
            BufSupport[i] = EMPTY_VALUE;
        }
        if(BufResistance[i] != EMPTY_VALUE && close[i] > BufResistance[i]) {
            BufResistance[i] = EMPTY_VALUE;
        }
    }

    return(rates_total);
}
