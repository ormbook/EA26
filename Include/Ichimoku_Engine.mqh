//+------------------------------------------------------------------+
//|                                              Ichimoku_Engine.mqh |
//|                   Macro Trend Rider (Engine E)                   |
//+------------------------------------------------------------------+
#property copyright "AI Converted"
#property version   "1.00"

class CIchimoku_Engine
{
private:
    int m_handle;
    
public:
    CIchimoku_Engine() { m_handle = INVALID_HANDLE; }
    ~CIchimoku_Engine() { if(m_handle != INVALID_HANDLE) IndicatorRelease(m_handle); }
    
    bool Init(string sym, ENUM_TIMEFRAMES tf, int tenkan=9, int kijun=26, int senkou=52)
    {
        m_handle = iIchimoku(sym, tf, tenkan, kijun, senkou);
        return (m_handle != INVALID_HANDLE);
    }
    
    // Returns 1 for Bullish Breakout, -1 for Bearish Breakout, 0 for None
    int GetSignal(string sym, ENUM_TIMEFRAMES tf)
    {
        if(m_handle == INVALID_HANDLE) return 0;
        
        double tenkan[2], kijun[2], spanA[2], spanB[2];
        if(CopyBuffer(m_handle, 0, 0, 2, tenkan) <= 0) return 0;
        if(CopyBuffer(m_handle, 1, 0, 2, kijun) <= 0) return 0;
        if(CopyBuffer(m_handle, 2, 0, 2, spanA) <= 0) return 0; // Senkou A is shift 0 here
        if(CopyBuffer(m_handle, 3, 0, 2, spanB) <= 0) return 0; // Senkou B is shift 0 here
        
        double close0 = iClose(sym, tf, 0);
        double close1 = iClose(sym, tf, 1);
        
        // Bullish Signal: Price above Cloud, Tenkan > Kijun (Golden Cross recently)
        double cloudTop = MathMax(spanA[1], spanB[1]);
        double cloudBottom = MathMin(spanA[1], spanB[1]);
        
        if(close1 > cloudTop && tenkan[1] > kijun[1]) return 1;
        
        // Bearish Signal: Price below Cloud, Tenkan < Kijun (Death Cross recently)
        if(close1 < cloudBottom && tenkan[1] < kijun[1]) return -1;
        
        return 0;
    }
    
    // Check if we should exit (Price crosses Kijun-sen)
    bool ShouldExit(string sym, ENUM_TIMEFRAMES tf, int positionType)
    {
        if(m_handle == INVALID_HANDLE) return false;
        double kijun[2];
        if(CopyBuffer(m_handle, 1, 0, 2, kijun) <= 0) return false;
        
        double close1 = iClose(sym, tf, 1);
        
        if(positionType == POSITION_TYPE_BUY) {
            // Exit if Price closes below Kijun
            if(close1 < kijun[1]) return true;
        }
        else if(positionType == POSITION_TYPE_SELL) {
            // Exit if Price closes above Kijun
            if(close1 > kijun[1]) return true;
        }
        return false;
    }
};
