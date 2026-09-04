//+------------------------------------------------------------------+
//|                                                   SMC_Engine.mqh |
//|                     Multi-Timeframe Market Structure & FVG Logic |
//+------------------------------------------------------------------+
#property copyright "AI Converted"
#property version   "1.10"

struct SMC_Zone {
    bool   active;
    bool   isBull;
    double top;
    double bottom;
    double poc;
    datetime time_start;
};

class CSMC_Engine {
private:
    int m_length;
    
    int CalculateDH(const MqlRates &rates[], int index, int count) {
        int sum = 0;
        for(int k=0; k<count; k++) {
            if(index-k-1 < 0) return 0;
            if(rates[index-k].high > rates[index-k-1].high) sum += 1;
            else if(rates[index-k].high < rates[index-k-1].high) sum -= 1;
        }
        return sum;
    }

    int CalculateDL(const MqlRates &rates[], int index, int count) {
        int sum = 0;
        for(int k=0; k<count; k++) {
            if(index-k-1 < 0) return 0;
            if(rates[index-k].low > rates[index-k-1].low) sum += 1;
            else if(rates[index-k].low < rates[index-k-1].low) sum -= 1;
        }
        return sum;
    }

public:
    CSMC_Engine() { m_length = 5; }
    
    // 1. Scan Market Structure (Trend)
    int GetMarketStructure(string sym, ENUM_TIMEFRAMES tf) {
        MqlRates rates[];
        if(CopyRates(sym, tf, 0, 200, rates) < 200) return 0;
        
        int p = m_length / 2;
        int current_os = 0;
        
        double upper_value = 0;
        bool upper_iscrossed = true;
        
        double lower_value = 0;
        bool lower_iscrossed = true;
        
        for(int i = m_length; i < 200; i++) {
            int dh = CalculateDH(rates, i, p);
            int dh_p = CalculateDH(rates, i-p, p);
            int dl = CalculateDL(rates, i, p);
            int dl_p = CalculateDL(rates, i-p, p);
            
            if(dh == -p && dh_p == p) {
                double maxH = rates[i].high;
                for(int k=1; k<m_length; k++) {
                    if(rates[i-k].high > maxH) maxH = rates[i-k].high;
                }
                if(rates[i-p].high == maxH) {
                    upper_value = rates[i-p].high;
                    upper_iscrossed = false;
                }
            }
            
            if(dl == p && dl_p == -p) {
                double minL = rates[i].low;
                for(int k=1; k<m_length; k++) {
                    if(rates[i-k].low < minL) minL = rates[i-k].low;
                }
                if(rates[i-p].low == minL) {
                    lower_value = rates[i-p].low;
                    lower_iscrossed = false;
                }
            }
            
            if(!upper_iscrossed && rates[i-1].close <= upper_value && rates[i].close > upper_value) {
                upper_iscrossed = true;
                current_os = 1;
            }
            if(!lower_iscrossed && rates[i-1].close >= lower_value && rates[i].close < lower_value) {
                lower_iscrossed = true;
                current_os = -1;
            }
        }
        return current_os;
    }
    
    // 2. Scan and return multiple active FVGs (for multi-block layering)
    int GetActiveFVGs(string sym, ENUM_TIMEFRAMES tf, bool getBull, SMC_Zone &out[], int max_count=3) {
        MqlRates rates[];
        int copied = CopyRates(sym, tf, 0, 500, rates);
        if(copied < 3) return 0;
        
        SMC_Zone active_fvgs[];
        
        for(int i = 2; i < copied; i++) {
            double bull_gap = rates[i].low - rates[i-2].high;
            double bear_gap = rates[i-2].low - rates[i].high;
            
            // Bull FVG
            if(rates[i].low > rates[i-2].high && rates[i-1].high > rates[i-2].high && bull_gap > 0) {
                int idx = ArraySize(active_fvgs);
                ArrayResize(active_fvgs, idx+1);
                active_fvgs[idx].active = true;
                active_fvgs[idx].isBull = true;
                active_fvgs[idx].top = rates[i].low;
                active_fvgs[idx].bottom = rates[i-2].high;
                active_fvgs[idx].time_start = rates[i-1].time;
                active_fvgs[idx].poc = active_fvgs[idx].bottom + (active_fvgs[idx].top - active_fvgs[idx].bottom)/2.0;
                
                MqlRates ltf[];
                ENUM_TIMEFRAMES volTf = PERIOD_M5;
                if(tf == PERIOD_M15) volTf = PERIOD_M1;
                if(tf == PERIOD_H1) volTf = PERIOD_M5;
                if(tf == PERIOD_H4) volTf = PERIOD_M15;
                if(tf == PERIOD_D1) volTf = PERIOD_H1;
                
                if(CopyRates(sym, volTf, rates[i-1].time, rates[i].time-1, ltf) > 0) {
                    double maxVol = 0;
                    double bestPrice = active_fvgs[idx].poc;
                    double binSize = (active_fvgs[idx].top - active_fvgs[idx].bottom) / 15.0;
                    double vols[15] = {0};
                    
                    for(int j=0; j<ArraySize(ltf); j++) {
                        for(int k=0; k<15; k++) {
                            double mid = active_fvgs[idx].bottom + k*binSize + binSize/2.0;
                            if(MathAbs(ltf[j].close - mid) <= binSize) {
                                vols[k] += (double)ltf[j].tick_volume;
                            }
                        }
                    }
                    for(int k=0; k<15; k++) {
                        if(vols[k] > maxVol) { maxVol = vols[k]; bestPrice = active_fvgs[idx].bottom + k*binSize + binSize/2.0; }
                    }
                    active_fvgs[idx].poc = bestPrice;
                }
            }
            
            // Bear FVG
            if(rates[i].high < rates[i-2].low && rates[i-1].low < rates[i-2].low && bear_gap > 0) {
                int idx = ArraySize(active_fvgs);
                ArrayResize(active_fvgs, idx+1);
                active_fvgs[idx].active = true;
                active_fvgs[idx].isBull = false;
                active_fvgs[idx].top = rates[i-2].low;
                active_fvgs[idx].bottom = rates[i].high;
                active_fvgs[idx].time_start = rates[i-1].time;
                active_fvgs[idx].poc = active_fvgs[idx].bottom + (active_fvgs[idx].top - active_fvgs[idx].bottom)/2.0;
                
                MqlRates ltf[];
                ENUM_TIMEFRAMES volTf = PERIOD_M5;
                if(tf == PERIOD_M15) volTf = PERIOD_M1;
                if(tf == PERIOD_H1) volTf = PERIOD_M5;
                if(tf == PERIOD_H4) volTf = PERIOD_M15;
                if(tf == PERIOD_D1) volTf = PERIOD_H1;
                
                if(CopyRates(sym, volTf, rates[i-1].time, rates[i].time-1, ltf) > 0) {
                    double maxVol = 0;
                    double bestPrice = active_fvgs[idx].poc;
                    double binSize = (active_fvgs[idx].top - active_fvgs[idx].bottom) / 15.0;
                    double vols[15] = {0};
                    
                    for(int j=0; j<ArraySize(ltf); j++) {
                        for(int k=0; k<15; k++) {
                            double mid = active_fvgs[idx].bottom + k*binSize + binSize/2.0;
                            if(MathAbs(ltf[j].close - mid) <= binSize) {
                                vols[k] += (double)ltf[j].tick_volume;
                            }
                        }
                    }
                    for(int k=0; k<15; k++) {
                        if(vols[k] > maxVol) { maxVol = vols[k]; bestPrice = active_fvgs[idx].bottom + k*binSize + binSize/2.0; }
                    }
                    active_fvgs[idx].poc = bestPrice;
                }
            }
            
            // Mitigation check (Candle closes beyond POC = Used)
            for(int f=0; f<ArraySize(active_fvgs); f++) {
                if(!active_fvgs[f].active) continue;
                if(active_fvgs[f].isBull && rates[i].close < active_fvgs[f].poc) active_fvgs[f].active = false;
                if(!active_fvgs[f].isBull && rates[i].close > active_fvgs[f].poc) active_fvgs[f].active = false;
            }
        }
        
        // Populate out[] with most recent active FVGs
        int c = 0;
        ArrayResize(out, max_count);
        for(int f=ArraySize(active_fvgs)-1; f>=0; f--) {
            if(active_fvgs[f].active && active_fvgs[f].isBull == getBull) {
                out[c] = active_fvgs[f];
                c++;
                if(c >= max_count) break;
            }
        }
        ArrayResize(out, c);
        return c;
    }
    
    // Fallback for Dashboard (gets the absolute latest FVG regardless of direction)
    SMC_Zone GetLatestFVG(string sym, ENUM_TIMEFRAMES tf) {
        SMC_Zone zone;
        zone.active = false;
        SMC_Zone temp_b[]; SMC_Zone temp_s[];
        int b_count = GetActiveFVGs(sym, tf, true, temp_b, 1);
        int s_count = GetActiveFVGs(sym, tf, false, temp_s, 1);
        
        if(b_count > 0 && s_count > 0) {
            if(temp_b[0].time_start > temp_s[0].time_start) return temp_b[0];
            else return temp_s[0];
        } else if(b_count > 0) {
            return temp_b[0];
        } else if(s_count > 0) {
            return temp_s[0];
        }
        return zone;
    }
    
    // 3. Scan Liquidation Points
    void GetLiquidationZones(string sym, ENUM_TIMEFRAMES tf, double &bsl, double &ssl) {
        MqlRates rates[];
        if(CopyRates(sym, tf, 0, 100, rates) < 100) return;
        bsl = 0; ssl = 999999;
        
        int p = 5;
        for(int i=p; i<100-p; i++) {
            bool isHigh = true;
            bool isLow = true;
            for(int k=1; k<=p; k++) {
                if(rates[i].high <= rates[i-k].high || rates[i].high <= rates[i+k].high) isHigh = false;
                if(rates[i].low >= rates[i-k].low || rates[i].low >= rates[i+k].low) isLow = false;
            }
            if(isHigh && rates[i].high > bsl) bsl = rates[i].high;
            if(isLow && rates[i].low < ssl) ssl = rates[i].low;
        }
    }
    
    // 5. Check Fresh Breakout (BOS) with RSI Divergence
    int CheckBreakoutDivergence(string sym, ENUM_TIMEFRAMES tf) {
        MqlRates rates[];
        if(CopyRates(sym, tf, 0, 100, rates) < 100) return 0;
        
        double rsi[];
        int rsi_handle = iRSI(sym, tf, 14, PRICE_CLOSE);
        if(CopyBuffer(rsi_handle, 0, 0, 100, rsi) < 100) { IndicatorRelease(rsi_handle); return 0; }
        IndicatorRelease(rsi_handle);
        
        int p = 5; // Swing detection period
        int last_closed = 100 - 2; // Index of the last fully closed candle (98)
        
        // Find latest swing high before the breakout candle
        double swing_high = 0;
        double swing_high_rsi = 0;
        for(int i = last_closed - 1 - p; i >= p; i--) { 
            bool isHigh = true;
            for(int k=1; k<=p; k++) {
                if(rates[i].high <= rates[i-k].high || rates[i].high <= rates[i+k].high) { isHigh = false; break; }
            }
            if(isHigh) {
                swing_high = rates[i].high;
                swing_high_rsi = rsi[i];
                break;
            }
        }
        
        // Find latest swing low before the breakout candle
        double swing_low = 0;
        double swing_low_rsi = 0;
        for(int i = last_closed - 1 - p; i >= p; i--) { 
            bool isLow = true;
            for(int k=1; k<=p; k++) {
                if(rates[i].low >= rates[i-k].low || rates[i].low >= rates[i+k].low) { isLow = false; break; }
            }
            if(isLow) {
                swing_low = rates[i].low;
                swing_low_rsi = rsi[i];
                break;
            }
        }
        
        // Check if the freshly closed candle broke the swing
        if(swing_high > 0 && rates[last_closed].close > swing_high && rates[last_closed-1].close <= swing_high) {
            // Bullish BOS
            double breakout_rsi = rsi[last_closed];
            bool is_divergence = (breakout_rsi < swing_high_rsi); // Price made HH, but RSI made LH
            return is_divergence ? 1 : 2; // 1 = Breakout with Div (Weak), 2 = Breakout without Div (Strong)
        }
        
        if(swing_low > 0 && rates[last_closed].close < swing_low && rates[last_closed-1].close >= swing_low) {
            // Bearish BOS
            double breakout_rsi = rsi[last_closed];
            bool is_divergence = (breakout_rsi > swing_low_rsi); // Price made LL, but RSI made HL
            return is_divergence ? -1 : -2; // -1 = Breakout with Div (Weak), -2 = Breakout without Div (Strong)
        }
        
        return 0;
    }
};
