//+------------------------------------------------------------------+
//|           Zenflow EMA Master Trade PRO ver 5.3                 |
//|                                                                  |
//| CHIẾN LƯỢC TỔNG QUAN:                                            |
//|                                                                  |
//| 1. XU HƯỚNG (Trend Engine)                                       |
//|    - EMA Ribbon xếp chồng: 10, 15, 20, 50, 90, 120               |
//|    - Chỉ giao dịch thuận xu hướng chính                          |
//|                                                                  |
//| 2. VÙNG VÀO LỆNH (Pullback Zone)                                 |
//|    - Giá bắt buộc test lại EMA 20                                |
//|                                                                  |
//| 3. ENTRY PATTERN (Price Action Engine)                           |
//|    - Pinbar (Rejection)                                          |
//|    - Engulfing (Momentum Break)                                  |
//|    - Triple Inside (Structure Shift)                             |
//|    - Sweep Reversal (Liquidity Grab + Reclaim)                   |
//|    - Pinbar Break (Fake Break Continuation)                      |
//|    - Có thể bật/tắt từng pattern                                 |
//|                                                                  |
//| 4. BỘ LỌC BẮT BUỘC                                                |
//|    - Nến tín hiệu phải đồng màu với hướng giao dịch              |
//|    - Có thể log tên pattern khi vào lệnh                         |
//|                                                                  |
//| 5. QUẢN LÝ VỐN (Risk Engine)                                     |
//|    - Risk theo % Equity                                          |
//|    - StopLoss dựa trên cấu trúc + buffer                         |
//|    - Equity Guard (Target Equity / Stop Equity)                  |
//|    - Hỗ trợ Pyramiding                                           |
//|                                                                  |
//| 6. QUẢN LÝ LỆNH                                                   |
//|    - Trailing theo EMA20                                         |
//|    - Đóng toàn bộ khi đạt Target Equity                          |
//|                                                                  |
//| 7. THỰC THI (Execution Engine)                                   |
//|    - Slippage control                                            |
//|    - Retry logic khi gửi lệnh                                    |
//|                                                                  |
//| 8. BỘ LỌC THỜI GIAN                                               |
//|    - Lọc theo giờ Việt Nam                                       |
//|    - Không giao dịch Thứ 7 & Chủ Nhật      
//+------------------------------------------------------------------+

/*
   UPDATE 22/02/2026
   1. Chỉnh sửa SL đúng ở vị trí highest và lowest thay vì SL đặt ở C0
   
   UPDATE 25/02/2026
   1. Chỉnh lại số nến chạm EMA20 để hoàn thiện hơn cho mẫu nến TripleInside
   2. Thêm điều kiện lọc entry: nến tín hiệu phải đóng trên/dưới EMA20 theo hướng BUY/SELL
   
   UPDATE 27/02/2026
   1. Thêm Risk Mode: Fixed Money
   2. Thêm input Timeframe cho EA trade
   3. Thêm mẫu nến Star (3 nến đảo chiều)

   UPDATE 05/03/2026
   1. Tách riêng hệ thống quản lý lệnh:
      - BreakEven Engine chạy mỗi tick (OnTick) để bảo vệ vốn ngay khi đạt X.R
      - Trailing Exit Engine chạy khi nến đóng để tránh nhiễu intrabar
   2. Thêm Trailing Exit theo EMA:
      - Chỉ kích hoạt khi đạt InpActiveTrailingXR (>= X.R)
      - BUY: đóng khi nến đóng dưới EMA trailing
      - SELL: đóng khi nến đóng trên EMA trailing
   3. Cải thiện cấu trúc Execution Engine:
      - Slippage control qua SetDeviationInPoints
      - Retry logic khi gửi lệnh
   4. Tối ưu logic OnTick:
      - Equity Guard kiểm tra mỗi tick
      - BreakEven xử lý realtime
      - Entry và Trailing chỉ xử lý khi xuất hiện nến mới
   5. Chuẩn hóa kiến trúc EA theo mô hình Engine:
      - Trend Engine
      - Entry Pattern Engine
      - Risk Engine
      - Position Management Engine
      - Execution Engine
      
[UPDATE 5.0] 18/3/2026
   1. Thêm tính năng nhồi lệnh Scalein khi lệnh chính chạm 1R
      - Lệnh chính -> BE + EMA exit
      - Lệnh Scalein -> EMA exit
   2. Thêm tính năng switch mode cho Chức năng nhồi lệnh Dương
      - Kiểm tra toàn bộ lệnh chính + Scalein
      - Chỉ kiểm tra lệnh chính
      
[UPDATE 5.1] 19/3/2026
   1. Thêm bật tắt nhồi lệnh scale in
   2. Thay % target -> số tiền cố định
   3. Thêm switch giữa thông báo Exit EMA và tự động Exit EMA

[UPDATE 5.2] 20/3/2026
   1. Thêm bật/tắt cho phép vào lot 0.01 nếu lotsize < 0.01

[UPDATE 5.3] 21/3/2026
   Nâng cấp mẫu nến morning và búa ngược cho chuẩn
*/

#property copyright "Expert MQL5 Professional"
#property version   "5.30"
#property strict

#include <Trade\Trade.mqh>

//--- INPUT PARAMETERS

input group "=== TIMEFRAME CONTROL ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1;

input group "=== RISK MODE CONTROL ==="
enum ENUM_RISK_MODE
{
   RISK_PERCENT = 0,
   RISK_FIXED_MONEY = 1
};
input ENUM_RISK_MODE InpRiskMode = RISK_PERCENT;
input double   InpFixedRiskMoney = 100.0; // Risk Money
input double   InpRiskPercent    = 1.0;    // Risk %
input bool     AllowMinLotOverride = true; // Cho phép vào 0,01 nếu Lotsize < 0,01

input group "=== QUẢN LÝ VỐN & EQUITY GUARD ==="
input double   InpTargetEquity   = 10800.0; // Equity target tuyệt đối
input double   InpStopEquity     = 9500.0;  // Equity stop tuyệt đối
input bool     InpUseEquityGuard = true;   // Bật/Tắt tính năng bảo vệ Equity


input group "=== Quản lý lệnh ==="
input double   InpRewardRatio    = 5.0;    // TP mục tiêu (R:R)
input int      InpMaxDeviation = 100;      // Chấp nhận trượt giá (Points) - Vàng: 100-150, BTC: 300-500
input int      InpSLBufferPoints = 100; // Buffer SL (points) – XAU ~100–300
input bool     InpUseScaleIn = true; // Bật/Tắt nhồi lệnh Scale-in
enum AddPositionMode
{
   ADD_ALL = 0,     // Nhồi - kiểm tra tất cả lệnh
   ADD_MAIN_ONLY    // Nhồi - kiểm tra lệnh chính
};
input AddPositionMode InpAddMode = ADD_MAIN_ONLY;

input group "=== TRAILING CONTROL ==="
input bool   UseBreakEven      = true;
input double InpBreakEvenXR    = 1.0;   // đạt 1R thì BE
input bool   UseEMA20Trailing  = true;
input bool   UseEMAExitAlert = true;   // true = chỉ cảnh báo, false = auto đóng
input int     InpTrailingEMA = 20;
input double InpActiveTrailingXR = 1.5; // trailing sau 1.5R
input int      InpMagicNum         = 888999;


input group "=== EMA ENABLE CONTROL ==="
input bool UseEMA10  = true;
input bool UseEMA15  = true;
input bool UseEMA20  = true;
input bool UseEMA50  = true;
input bool UseEMA90  = true;
input bool UseEMA120 = true;

input group "=== THÔNG SỐ EMA RIBBON ==="
input int      InpEma10 = 10, InpEma15 = 15, InpEma20 = 20;
input int      InpEma50 = 50, InpEma90 = 60, InpEma120= 80;

input group "=== PULLBACK CONTROL ==="
input int  InpPullbackEMA = 20;     // EMA dùng để pullback (10,15,20,50...)


input group "=== ENTRY PATTERN CONTROL ==="
input bool UsePinbar        = true;
input bool UseEngulf        = true;
input bool UseTripleInside  = true;
input bool UseSweepReversal = true;
input bool UsePinbarBreak = true;
input bool UseStar = true;


input group "=== BỘ LỌC THỜI GIAN (GIỜ VIỆT NAM) ==="
input int      InpStartHourVT  = 14;       // Giờ bắt đầu (0-23h VN)
input int      InpStartMinuteVT = 0;        // Phút bắt đầu
input int      InpEndHourVT    = 23;       // Giờ kết thúc (0-23h VN)
input int      InpEndMinuteVT  = 0;        // Phút kết thúc
input bool     InpUseTimeFilter = true;    // Bật/Tắt bộ lọc thời gian

//--- BIẾN TOÀN CỤC
int      hEma10, hEma15, hEma20, hEma50, hEma90, hEma120;
int   hPullbackEMA;
int hTrailingEMA;
datetime last_bar_time = 0;
bool     IsBotStopped = false; 
double g_StartEquity   = 0.0;
double g_TargetEquity  = 0.0;
double g_StopEquity    = 0.0;
ulong alertedTickets[500];
int alertedCount = 0;


CTrade   m_trade;

//+------------------------------------------------------------------+
//| KHỞI TẠO EA                                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   if(UseEMA10)
      hEma10  = iMA(_Symbol, InpTimeframe, InpEma10, 0, MODE_EMA, PRICE_CLOSE);
   
   if(UseEMA15)
      hEma15  = iMA(_Symbol, InpTimeframe, InpEma15, 0, MODE_EMA, PRICE_CLOSE);
   
   if(UseEMA20)
      hEma20  = iMA(_Symbol, InpTimeframe, InpEma20, 0, MODE_EMA, PRICE_CLOSE);
   
   if(UseEMA50)
      hEma50  = iMA(_Symbol, InpTimeframe, InpEma50, 0, MODE_EMA, PRICE_CLOSE);
   
   if(UseEMA90)
      hEma90  = iMA(_Symbol, InpTimeframe, InpEma90, 0, MODE_EMA, PRICE_CLOSE);
   
   if(UseEMA120)
      hEma120 = iMA(_Symbol, InpTimeframe, InpEma120, 0, MODE_EMA, PRICE_CLOSE);
   
   if((UseEMA10  && hEma10  == INVALID_HANDLE) ||
      (UseEMA15  && hEma15  == INVALID_HANDLE) ||
      (UseEMA20  && hEma20  == INVALID_HANDLE) ||
      (UseEMA50  && hEma50  == INVALID_HANDLE) ||
      (UseEMA90  && hEma90  == INVALID_HANDLE) ||
      (UseEMA120 && hEma120 == INVALID_HANDLE))
   {
      Alert("EMA handle creation failed - EA dừng.");
      Print("EMA handle creation failed");
      return INIT_FAILED;
   }
   
   hPullbackEMA = iMA(_Symbol, InpTimeframe, InpPullbackEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hPullbackEMA == INVALID_HANDLE)
   {
      Print("Pullback EMA handle failed");
      return INIT_FAILED;
   }
   
   hTrailingEMA = iMA(_Symbol, InpTimeframe, InpTrailingEMA, 0, MODE_EMA, PRICE_CLOSE);
         
   m_trade.SetExpertMagicNumber(InpMagicNum);
   // --- THÊM DÒNG NÀY VÀO ĐÂY ---
   m_trade.SetDeviationInPoints(InpMaxDeviation); // Chấp nhận trượt 50 points (5 pips)
   // -----------------------------
   IsBotStopped = false;
   
   // --- EQUITY BASELINE ---
   g_StartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   
   g_TargetEquity = InpTargetEquity;
   g_StopEquity   = InpStopEquity;
      
   PrintFormat(
      "EQUITY GUARD INIT | Start: %.2f | Target: %.2f | Stop: %.2f",
      g_StartEquity, g_TargetEquity, g_StopEquity
   );

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| SỰ KIỆN ON TICK                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   if(IsBotStopped) return; 
   
   // --- 1. KIỂM TRA EQUITY GUARD (KIỂM TRA MỖI TICK) ---
   if(InpUseEquityGuard)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(currentEquity >= g_TargetEquity || currentEquity <= g_StopEquity)
      {
         CloseAllPositions();
         IsBotStopped = true;
         Alert(StringFormat("EQUITY GUARD ACTIVATED | Equity: %.2f", currentEquity));
         return;
      }
   }
   
   CheckAndCleanPending();

   // --- 2. BREAK EVEN (KIỂM TRA MỖI TICK) ---
   // Hàm này dời SL về Entry ngay khi đạt X.R, không cần chờ đóng nến
   CheckBreakEvenOnTick(); 

   // --- 3. KIỂM TRA THỜI GIAN & NẾN MỚI ---
   if(!IsTradingTime()) return; 

   datetime current_time = iTime(_Symbol, InpTimeframe, 0);
   if(current_time == last_bar_time) return; // Nếu chưa đóng nến thì dừng tại đây
   
   // --- PHẦN CODE DƯỚI ĐÂY CHỈ CHẠY 1 LẦN KHI NẾN MỚI XUẤT HIỆN ---

   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpTimeframe, 0, 10, r) < 10) return;
   
   // --- 4. QUẢN LÝ THOÁT LỆNH THEO EMA (KHI NẾN ĐÓNG) ---
   double eTrail = GetMA(hTrailingEMA, 1);
   CheckTrailingExitOnClose(r, eTrail); // Hàm thoát lệnh bạn muốn (đã tách riêng)

   // --- 5. LẤY GIÁ TRỊ EMA XÁC ĐỊNH XU HƯỚNG ---
   double pullBuf[];
   ArraySetAsSeries(pullBuf, true);
   if(CopyBuffer(hPullbackEMA, 0, 0, 3, pullBuf) < 3) return;
   double ePull = pullBuf[1];

   // --- 4. LẤY GIÁ TRỊ EMA XÁC ĐỊNH XU HƯỚNG ---
   double e10  = GetMA(hEma10, 1);
   double e15  = GetMA(hEma15, 1);
   double e20  = GetMA(hEma20, 1);
   double e50  = GetMA(hEma50, 1);
   double e90  = GetMA(hEma90, 1);
   double e120 = GetMA(hEma120, 1);

   bool isTrendBuy = true;
   bool isTrendSell = true;
   
   if(UseEMA10 && UseEMA15)
   {
      if(!(e10 > e15)) isTrendBuy = false;
      if(!(e10 < e15)) isTrendSell = false;
   }
   
   if(UseEMA15 && UseEMA20)
   {
      if(!(e15 > e20)) isTrendBuy = false;
      if(!(e15 < e20)) isTrendSell = false;
   }
   
   if(UseEMA20 && UseEMA50)
   {
      if(!(e20 > e50)) isTrendBuy = false;
      if(!(e20 < e50)) isTrendSell = false;
   }
   
   if(UseEMA50 && UseEMA90)
   {
      if(!(e50 > e90)) isTrendBuy = false;
      if(!(e50 < e90)) isTrendSell = false;
   }
   
   if(UseEMA90 && UseEMA120)
   {
      if(!(e90 > e120)) isTrendBuy = false;
      if(!(e90 < e120)) isTrendSell = false;
   }

   // --- 5. TÌM TÍN HIỆU VÀO LỆNH ---
   if(isTrendBuy || isTrendSell)
   {
      string patternName;
      int signal = CheckSignal(r, ePull, isTrendBuy, isTrendSell, patternName);
   
      if(signal != 0)
      {
         int barsCount = GetPatternBarsCount(patternName);
   
         double sl = 0.0;
   
         if(signal == 1) // BUY
         {
            double structureLow = GetPatternLowest(r, barsCount);
            sl = structureLow - InpSLBufferPoints * _Point;
   
            if(CheckPyramiding(true, sl))
            {
               PrintFormat(
                  "BUY | Pattern=%s | Bars=%d | StructureLow=%.2f | FinalSL=%.2f",
                  patternName, barsCount, structureLow, sl
               );
   
               ExecuteOrder(ORDER_TYPE_BUY, sl, r[1].close);
            }
         }
   
         if(signal == -1) // SELL
         {
            double structureHigh = GetPatternHighest(r, barsCount);
            sl = structureHigh + InpSLBufferPoints * _Point;
   
            if(CheckPyramiding(false, sl))
            {
               PrintFormat(
                  "SELL | Pattern=%s | Bars=%d | StructureHigh=%.2f | FinalSL=%.2f",
                  patternName, barsCount, structureHigh, sl
               );
   
               ExecuteOrder(ORDER_TYPE_SELL, sl, r[1].close);
            }
         }
      }
   }

   last_bar_time = current_time;
}


// --- HÀM 1: CHẠY TRÊN MỖI TICK ĐỂ BẢO VỆ VỐN NGAY LẬP TỨC ---
// --- HÀM 1: BREAK EVEN ---
void CheckBreakEvenOnTick()
{
   if(!UseBreakEven) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i); 
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      
      // 🔥 FILTER MAGIC + SYMBOL
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNum || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      // 🔥 FILTER CHỈ LỆNH 1
      string comment = PositionGetString(POSITION_COMMENT);
      if(comment != "ZenFlow Pro") continue;

      long   type         = PositionGetInteger(POSITION_TYPE);
      double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL    = PositionGetDouble(POSITION_SL);
      double tp           = PositionGetDouble(POSITION_TP);
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double risk = MathAbs(openPrice - currentSL);
      if(risk <= 0) continue;

      double profitDistance = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);

      if(profitDistance >= risk * InpBreakEvenXR)
      {
         bool needMove = false;
         
         if(type == POSITION_TYPE_BUY && NormalizeDouble(currentSL - openPrice, _Digits) < 0) 
            needMove = true;
            
         if(type == POSITION_TYPE_SELL && (NormalizeDouble(currentSL - openPrice, _Digits) > 0 || currentSL == 0)) 
            needMove = true;

         if(needMove)
         {
            if(!m_trade.PositionModify(ticket, openPrice, tp))
               Print("Lỗi Modify: ", m_trade.ResultRetcodeDescription());
            else
               PrintFormat("BREAK EVEN SUCCESS | Ticket=%I64u", ticket);
         }
      }
   }
}

// --- HÀM 2: CHẠY KHI ĐÓNG NẾN (CANDLE CLOSE) ĐỂ THOÁT LỆNH THEO EMA ---
void CheckTrailingExitOnClose(MqlRates &r[], double emaTrailing)
{
   if(!UseEMA20Trailing) return;

   double closePrice = r[1].close;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNum) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);

      bool allowExit = false;

      // 🔥 LỆNH 1 → phải BE mới được thoát
      if(comment == "ZenFlow Pro")
      {
         if(type == POSITION_TYPE_BUY && sl >= openPrice) allowExit = true;
         if(type == POSITION_TYPE_SELL && sl > 0 && sl <= openPrice) allowExit = true;
      }

      // 🔥 LỆNH 2 → luôn được EMA exit
      if(comment == "ScaleIn")
      {
         allowExit = true;
      }

      if(!allowExit) continue;

      // --- EMA EXIT ---
      if(type == POSITION_TYPE_BUY && closePrice < emaTrailing)
      {
         if(UseEMAExitAlert)
         {
            if(!AlreadyAlerted(ticket))
            {
               string msg = StringFormat(
                  "EMA EXIT SIGNAL (BUY)\n%s | Ticket=%I64u | Close: %.2f < EMA: %.2f",
                  _Symbol, ticket, closePrice, emaTrailing
               );
      
               Alert(msg);
               SendNotification(msg);
               Print(msg);
      
               MarkAlerted(ticket);
            }
         }
         else
         {
            m_trade.PositionClose(ticket);
            PrintFormat("EMA EXIT BUY | %s | Ticket=%I64u", comment, ticket);
         }
      }
      
      if(type == POSITION_TYPE_SELL && closePrice > emaTrailing)
      {
         if(UseEMAExitAlert)
         {
            if(!AlreadyAlerted(ticket))
            {
               string msg = StringFormat(
                  "EMA EXIT SIGNAL (SELL)\n%s | Ticket=%I64u | Close: %.2f > EMA: %.2f",
                  _Symbol, ticket, closePrice, emaTrailing
               );
      
               Alert(msg);
               SendNotification(msg);
               Print(msg);
      
               MarkAlerted(ticket);
            }
         }
         else
         {
            m_trade.PositionClose(ticket);
            PrintFormat("EMA EXIT SELL | %s | Ticket=%I64u", comment, ticket);
         }
      }
   }
}

void ResetAlertedTickets()
{
   alertedCount = 0;
}



bool AlreadyAlerted(ulong ticket)
{
   for(int i = 0; i < alertedCount; i++)
   {
      // 🔥 Nếu ticket đã chết → remove luôn
      if(!IsPositionStillAlive(alertedTickets[i]))
      {
         alertedTickets[i] = alertedTickets[alertedCount - 1];
         alertedCount--;
         i--; // 🔥 rất quan trọng: tránh skip phần tử
         continue;
      }

      // 🔥 Check ticket cần tìm
      if(alertedTickets[i] == ticket)
         return true;
   }
   return false;
}

void MarkAlerted(ulong ticket)
{
   if(alertedCount < 100)
      alertedTickets[alertedCount++] = ticket;
}

bool IsPositionStillAlive(ulong ticket)
{
   if(PositionSelectByTicket(ticket))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| HELPER: KIỂM TRA TÍN HIỆU NẾN (PINBAR / ENGULFING / TRIPLE INSIDE BAR ) (CÓ LỌC MÀU NẾN)
//+------------------------------------------------------------------+

bool isPinbarBuy(MqlRates &C0)
{
   double body = MathAbs(C0.close - C0.open);
   double lowerWick = MathMin(C0.open, C0.close) - C0.low;

   return (
      C0.close > C0.open &&
      body > 0 &&
      lowerWick >= body * 2
   );
}

bool isPinbarSell(MqlRates &C0)
{
   double body = MathAbs(C0.close - C0.open);
   double upperWick = C0.high - MathMax(C0.open, C0.close);

   return (
      C0.close < C0.open &&
      body > 0 &&
      upperWick >= body * 2
   );
}

bool isEngulfBuy(MqlRates &C0, MqlRates &C1)
{
   return (
      C1.close < C1.open &&
      C0.close > C0.open &&
      C0.close >= C1.open &&
      !(C0.high <= C1.high && C0.low >= C1.low)
   );
}

bool isEngulfSell(MqlRates &C0, MqlRates &C1)
{
   return (
      C1.close > C1.open &&
      C0.close < C0.open &&
      C0.close <= C1.open &&
      !(C0.high <= C1.high && C0.low >= C1.low)
   );
}

bool isTripleInsideBuy(MqlRates &C0, MqlRates &C1, MqlRates &C2)
{
   // C2 bearish
   if(!(C2.close < C2.open))
      return false;

   // C1 inside hoàn toàn C2
   if(!(C1.high < C2.high && C1.low > C2.low))
      return false;

   // C0 bullish
   if(!(C0.close > C0.open))
      return false;

   // Reclaim thân C2
   if(!(C0.close > C2.open))
      return false;

   // Break high C2
   if(!(C0.high > C2.high))
      return false;

   return true;
}


bool isTripleInsideSell(MqlRates &C0, MqlRates &C1, MqlRates &C2)
{
   // C2 bullish
   if(!(C2.close > C2.open))
      return false;

   // C1 inside hoàn toàn C2
   if(!(C1.high < C2.high && C1.low > C2.low))
      return false;

   // C0 bearish
   if(!(C0.close < C0.open))
      return false;

   // Reclaim thân C2
   if(!(C0.close < C2.open))
      return false;

   // Break low C2
   if(!(C0.low < C2.low))
      return false;

   return true;
}

bool isSweepReversalBuy(MqlRates &C0, MqlRates &C1)
{
   // C1 bearish
   if(!(C1.close < C1.open))
      return false;

   // C0 bullish
   if(!(C0.close > C0.open))
      return false;

   // Sweep low
   if(!(C0.low < C1.low))
      return false;

   // Đóng cửa trên midpoint C1
   double midC1 = (C1.high + C1.low) / 2.0;
   if(!(C0.close > midC1))
      return false;

   return true;
}


bool isSweepReversalSell(MqlRates &C0, MqlRates &C1)
{
   // C1 bullish
   if(!(C1.close > C1.open))
      return false;

   // C0 bearish
   if(!(C0.close < C0.open))
      return false;

   // Sweep high
   if(!(C0.high > C1.high))
      return false;

   // Đóng cửa dưới midpoint C1
   double midC1 = (C1.high + C1.low) / 2.0;
   if(!(C0.close < midC1))
      return false;

   return true;
}

bool isPinbarBreakBuy(MqlRates &C0, MqlRates &C1, MqlRates &C2)
{
   return (
      // C2 bearish impulse
      C2.close < C2.open &&

      // C1 pullback tăng (yếu)
      C1.close > C1.open &&
      C1.close < C2.open &&
      C1.high  > C2.high &&
      C1.low   > C2.low &&

      // C0 breakout xác nhận BOS
      C0.close > C0.open &&
      C0.close > C2.open
   );
}

bool isPinbarBreakSell(MqlRates &C0, MqlRates &C1, MqlRates &C2)
{
   return (
      // C2 bullish impulse
      C2.close > C2.open &&

      // C1 pullback giảm (yếu)
      C1.close < C1.open &&
      C1.close > C2.open &&
      C1.low   < C2.low &&
      C1.high  < C2.high &&

      // C0 breakout xác nhận BOS
      C0.close < C0.open &&
      C0.close < C2.open
   );
}

bool isMorningStar(MqlRates &C0, MqlRates &C1, MqlRates &C2)
{
   // ===== C2: Bearish impulse =====
   if(C2.close >= C2.open)
      return false;

   // ===== Midpoint C2 =====
   double midC2 = (C2.open + C2.close) / 2.0;

   // ===== C1: Sweep + weak bullish =====
   if(C1.close <= C1.open)   return false;
   if(C1.close >= midC2)     return false;
   if(C1.low   >= C2.low)    return false;
   if(C1.high  >= C2.high)   return false;

   // ===== C0: Confirm mạnh =====
   if(C0.close <= C0.open)   return false;
   if(C0.close <= midC2)     return false;

   double body0  = MathAbs(C0.close - C0.open);
   double range0 = C0.high - C0.low;

   if(range0 <= 0) return false; // tránh chia lỗi / nến lỗi
   if(body0 <= range0 * 0.7) return false; // momentum mạnh

   return true;
}

bool isEveningStar(MqlRates &C0, MqlRates &C1, MqlRates &C2)
{
   // ===== C2: Bullish impulse =====
   if(C2.close <= C2.open)
      return false;

   // ===== Midpoint C2 =====
   double midC2 = (C2.open + C2.close) / 2.0;

   // ===== C1: Sweep + weak bearish =====
   if(C1.close >= C1.open)   return false;
   if(C1.close <= midC2)     return false;
   if(C1.high  <= C2.high)   return false;
   if(C1.low   <= C2.low)    return false;

   // ===== C0: Confirm mạnh =====
   if(C0.close >= C0.open)   return false;
   if(C0.close >= midC2)     return false;

   double body0  = MathAbs(C0.open - C0.close);
   double range0 = C0.high - C0.low;

   if(range0 <= 0) return false;
   if(body0 <= range0 * 0.7) return false;

   return true;
}

//+------------------------------------------------------------------+
//| HELPER: Check tín hiệu nến với EMA 20
//+------------------------------------------------------------------+
int CheckSignal(MqlRates &r[],double ema20,bool isTrendBuy,bool isTrendSell,string &pattern)
{
   pattern="";
   MqlRates C0=r[1];
   MqlRates C1=r[2];
   MqlRates C2=r[3];

   int signal=0;

   // ================= BUY =================
   if(isTrendBuy)
   {
      // ===== PINBAR BUY =====
      if(UsePinbar && isPinbarBuy(C0))
      {
         if(!(C0.low<=ema20 && C0.high>=ema20)) return 0;
         if(C0.close<=ema20) return 0;
         pattern="PinbarBuy";
         return 1;
      }
   
      // ===== ENGULF BUY =====
      if(UseEngulf && isEngulfBuy(C0,C1))
      {
         bool touched =
            (C1.low<=ema20 && C1.high>=ema20) ||
            (C0.low<=ema20 && C0.high>=ema20);
   
         if(!touched) return 0;
         if(C0.close<=ema20) return 0;
         pattern="EngulfBuy";
         return 1;
      }
   
      // ===== TRIPLE INSIDE BUY =====
      if(UseTripleInside && isTripleInsideBuy(C0,C1,C2))
      {
         bool touched =
            (C2.low<=ema20 && C2.high>=ema20) ||
            (C1.low<=ema20 && C1.high>=ema20);
   
         if(!touched) return 0;
         if(C0.close<=ema20) return 0;
   
         pattern="TripleInsideBuy";
         return 1;
      }
   
      // ===== SWEEP BUY =====
      if(UseSweepReversal && isSweepReversalBuy(C0,C1))
      {
         if(!(C0.low<=ema20 && C0.high>=ema20)) return 0;
         if(C0.close<=ema20) return 0;
         pattern="SweepBuy";
         return 1;
      } 
      
            // ===== PINBAR BREAK BUY =====
      if(UsePinbarBreak && isPinbarBreakBuy(C0,C1,C2))
      {
         bool touched =
            (C2.low<=ema20 && C2.high>=ema20) ||
            (C1.low<=ema20 && C1.high>=ema20);
      
         if(!touched) return 0;
         if(C0.close<=ema20) return 0;
      
         pattern="PinbarBreakBuy";
         return 1;
      }
      
      // ===== MorningStar BUY =====   
      if(UseStar && isMorningStar(C0,C1,C2))
      {
         bool touched =
            (C2.low<=ema20 && C2.high>=ema20) ||
            (C1.low<=ema20 && C1.high>=ema20);
      
         if(!touched) return 0;
         if(C0.close<=ema20) return 0;
      
         pattern="MorningStar";
         return 1;
      }
   }

   // ================= SELL =================
   if(isTrendSell)
   {
      // ===== PINBAR SELL =====
      if(UsePinbar && isPinbarSell(C0))
      {
         if(!(C0.low<=ema20 && C0.high>=ema20)) return 0;
         if(C0.close>=ema20) return 0;
         pattern="PinbarSell";
         return -1;
      }
   
      // ===== ENGULF SELL =====
      if(UseEngulf && isEngulfSell(C0,C1))
      {
         bool touched =
            (C1.low<=ema20 && C1.high>=ema20) ||
            (C0.low<=ema20 && C0.high>=ema20);
   
         if(!touched) return 0;
         if(C0.close>=ema20) return 0;
         pattern="EngulfSell";
         return -1;
      }
   
      // ===== TRIPLE INSIDE SELL =====
      if(UseTripleInside && isTripleInsideSell(C0,C1,C2))
      {
         bool touched =
            (C2.low<=ema20 && C2.high>=ema20) ||
            (C1.low<=ema20 && C1.high>=ema20);
   
         if(!touched) return 0;
         if(C0.close>=ema20) return 0;
   
         pattern="TripleInsideSell";
         return -1;
      }
   
      // ===== SWEEP SELL =====
      if(UseSweepReversal && isSweepReversalSell(C0,C1))
      {
         if(!(C0.low<=ema20 && C0.high>=ema20)) return 0;
         if(C0.close>=ema20) return 0;
         pattern="SweepSell";
         return -1;
      }
      
      // ===== PINBAR BREAK SELL =====
      if(UsePinbarBreak && isPinbarBreakSell(C0,C1,C2))
      {
         bool touched =
            (C2.low<=ema20 && C2.high>=ema20) ||
            (C1.low<=ema20 && C1.high>=ema20);
      
         if(!touched) return 0;
         if(C0.close>=ema20) return 0;
      
         pattern="PinbarBreakSell";
         return -1;
      }
      
      // ===== EveningStar SELL =====
      if(UseStar && isEveningStar(C0,C1,C2))
      {
         bool touched =
            (C2.low<=ema20 && C2.high>=ema20) ||
            (C1.low<=ema20 && C1.high>=ema20);
      
         if(!touched) return 0;
         if(C0.close>=ema20) return 0;
      
         pattern="EveningStar";
         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| HELPER: số nến trong mẫu nến entry                   |
//+------------------------------------------------------------------+
int GetPatternBarsCount(string patternName)
{
   if(patternName == "PinbarBuy" || patternName == "PinbarSell")
      return 1;

   if(patternName == "EngulfBuy" || patternName == "EngulfSell" ||
      patternName == "SweepBuy"  || patternName == "SweepSell")
      return 2;

   if(
      patternName == "TripleInsideBuy" || patternName == "TripleInsideSell" ||
      patternName == "PinbarBreakBuy"  || patternName == "PinbarBreakSell"  ||
      patternName == "MorningStar" || patternName == "EveningStar"
     ) return 3;

   return 1;
}

//+------------------------------------------------------------------+
//| HELPER: Tìm lowest và highest
//+------------------------------------------------------------------+
double GetPatternLowest(MqlRates &r[], int barsCount)
{
   double lowest = r[1].low;

   for(int i = 1; i <= barsCount; i++)
      if(r[i].low < lowest)
         lowest = r[i].low;

   return lowest;
}

double GetPatternHighest(MqlRates &r[], int barsCount)
{
   double highest = r[1].high;

   for(int i = 1; i <= barsCount; i++)
      if(r[i].high > highest)
         highest = r[i].high;

   return highest;
}

//+------------------------------------------------------------------+
//| HELPER: THỰC THI VÀO LỆNH & TÍNH LOT (FIXED)                     |
//+------------------------------------------------------------------+
void ExecuteOrder(ENUM_ORDER_TYPE type, double sl, double entry)
{
   //--- 1. Khoảng cách SL
   double dist = MathAbs(entry - sl);
   if(dist < _Point * 5) return; // SL quá sát → bỏ

   //--- 2. Tính lot theo RISK %
   double lot = CalculateLot(entry, sl);
   if(lot <= 0) return;

   //--- 3. Tính TP theo RR
   double tp = (type == ORDER_TYPE_BUY)
               ? entry + dist * InpRewardRatio
               : entry - dist * InpRewardRatio;

   int maxRetries = 3;
   bool success = false;

   for(int i = 0; i < maxRetries; i++)
   {
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) continue;

      double price = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;

      if(type == ORDER_TYPE_BUY)
         success = m_trade.Buy(lot, _Symbol, price, sl, tp, "ZenFlow Pro");
      else
         success = m_trade.Sell(lot, _Symbol, price, sl, tp, "ZenFlow Pro");

      uint ret = m_trade.ResultRetcode();

      if(success && (ret == TRADE_RETCODE_DONE || ret == TRADE_RETCODE_PLACED))
      {
         PrintFormat(
            "Z-ENTRY OK | %s | Lot: %.2f | Entry: %.2f | SL: %.2f | TP: %.2f",
            (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            lot, price, sl, tp
         );
      
         // 🔥 ĐỒNG BỘ SL TOÀN BỘ LỆNH CŨ
         SyncAllStopLoss(type == ORDER_TYPE_BUY, sl);
         
            // 🚀 SCALE-IN ORDER (LỆNH 2)
         if(InpUseScaleIn)
         {
            PlaceScaleInOrder(
               type == ORDER_TYPE_BUY,
               price,
               sl,
               tp,
               lot
            );
         }     
         break;
      }
      else
      {
         PrintFormat(
            "Retry %d failed | Retcode=%d (%s)",
            i+1, ret, m_trade.ResultRetcodeDescription()
         );
         Sleep(200);
      }
   }
}


//+------------------------------------------------------------------+
//| HELPER: PlaceScaleInOrder - Nhiệm vụ:Tính R,Tạo BUY STOP / SELL STOP, Tránh duplicate                           |
//+------------------------------------------------------------------+
void PlaceScaleInOrder(bool isBuy, double entry1, double sl1, double tp1, double lot)
{
   //--- Check đã có pending chưa
   if(HasPendingOrder()) return;

   double R = MathAbs(entry1 - sl1);
   if(R <= 0) return;

   double entry2 = isBuy ? entry1 + R : entry1 - R;
   double sl2    = entry1;
   double tp2    = tp1;

   bool success = false;

   if(isBuy)
   {
      success = m_trade.BuyStop(lot, entry2, _Symbol, sl2, tp2, ORDER_TIME_GTC, 0, "ScaleIn");
   }
   else
   {
      success = m_trade.SellStop(lot, entry2, _Symbol, sl2, tp2, ORDER_TIME_GTC, 0, "ScaleIn");
   }

   if(success)
   {
      PrintFormat("SCALE-IN PLACED | %s | Entry2=%.2f | SL=%.2f | TP=%.2f",
         isBuy ? "BUY STOP" : "SELL STOP",
         entry2, sl2, tp2);
   }
   else
   {
      Print("Scale-in order failed: ", m_trade.ResultRetcodeDescription());
   }
}


//+------------------------------------------------------------------+
//| HELPER: HasPendingOrder: 👉 Tránh spam nhiều lệnh                                |
//+------------------------------------------------------------------+
bool HasPendingOrder()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;

      if(!OrderSelect(ticket)) continue;

      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNum) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| HELPER: DeleteAllPendingOrders 👉 Gọi khi lệnh chính bị SL                                |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;

      if(!OrderSelect(ticket)) continue;

      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNum) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
      {
         if(!m_trade.OrderDelete(ticket))
            Print("Delete pending failed: ", m_trade.ResultRetcodeDescription());
         else
            PrintFormat("Pending deleted | Ticket=%I64u", ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| HELPER: CheckAndCleanPending                               |
//+------------------------------------------------------------------+
void CheckAndCleanPending()
{
   // Nếu không còn lệnh nào → xóa pending
   if(PositionsTotal() == 0)
   {
      DeleteAllPendingOrders();
      ResetAlertedTickets(); // 🔥 reset trạng thái alert
   }
}

//+------------------------------------------------------------------+
//| HELPER: ĐÓNG TOÀN BỘ LỆNH CỦA BOT                                |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNum)
            m_trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| HELPER: KIỂM TRA NHỒI LỆNH (PYRAMIDING)                          |
//+------------------------------------------------------------------+
bool CheckPyramiding(bool isBuy, double newSL)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNum) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);

      // 🔥 MODE: chỉ check lệnh chính
      if(InpAddMode == ADD_MAIN_ONLY && comment != "ZenFlow Pro")
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      if(isBuy && newSL < openPrice) return false;
      if(!isBuy && newSL > openPrice) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| HELPER: LẤY GIÁ TRỊ MA                                           |
//+------------------------------------------------------------------+
double GetMA(int handle, int shift) {
   double b[]; ArraySetAsSeries(b, true);
   if(CopyBuffer(handle, 0, shift, 1, b) <= 0) return 0;
   return b[0];
}


//+------------------------------------------------------------------+
//| CALCULATE LOT - FIXED (ALL BROKER / ALL PROP FIRM)                |
//+------------------------------------------------------------------+
double CalculateLot(double entryPrice, double slPrice)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = 0.0;
   
   if(InpRiskMode == RISK_PERCENT)
   {
      riskMoney = equity * InpRiskPercent / 100.0;
   }
   else if(InpRiskMode == RISK_FIXED_MONEY)
   {
      riskMoney = InpFixedRiskMoney;
   }
   
   // bảo vệ
   if(riskMoney <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      
   //--- xác định loại lệnh
   ENUM_ORDER_TYPE orderType;
   if(entryPrice > slPrice)
      orderType = ORDER_TYPE_BUY;
   else
      orderType = ORDER_TYPE_SELL;

   //--- tính lỗ của 1 lot nếu hit SL
   double lossPerLot = 0.0;
   if(!OrderCalcProfit(
         orderType,
         _Symbol,
         1.0,
         entryPrice,
         slPrice,
         lossPerLot))
   {
      Print("CalculateLot ERROR: OrderCalcProfit failed");
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }

   lossPerLot = MathAbs(lossPerLot);
   if(lossPerLot <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   //--- lot thô
   double rawLot = riskMoney / lossPerLot;
   
      //--- chuẩn hóa lot theo symbol
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // 🔥 Nếu lot tính ra nhỏ hơn minLot
   if(rawLot < minLot)
   {
      if(AllowMinLotOverride)
      {
         Print("⚠️ MinLot Override Activated | Using MIN LOT");
         return minLot;
      }
      else
      {
         Print("Lot < MinLot → Skip trade");
         return 0;
      }
   }


   double finalLot = MathFloor(rawLot / stepLot) * stepLot;
   finalLot = MathMax(minLot, MathMin(finalLot, maxLot));

   //--- check margin
   double marginRequired = 0.0;
   if(OrderCalcMargin(
         orderType,
         _Symbol,
         finalLot,
         entryPrice,
         marginRequired))
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginRequired > freeMargin)
      {
         double scale = freeMargin / marginRequired;
         finalLot = MathFloor((finalLot * scale) / stepLot) * stepLot;
         finalLot = MathMax(minLot, finalLot);
      }
   }
   
   // 🔥 ADD Ở ĐÂY
   if(finalLot < minLot)
   {
      if(AllowMinLotOverride)
      {
         finalLot = minLot;
         Print("⚠️ Force MIN LOT (override risk)");
      }
      else
      {
         Print("❌ Lot < MinLot → Skip trade");
         return 0;
      }
   }

   PrintFormat(
      "Z-LotCalc | Equity: %.2f | Risk: %.2f | Loss/1Lot: %.2f | FinalLot: %.2f",
      equity, riskMoney, lossPerLot, finalLot
   );

   return finalLot;
}

//+------------------------------------------------------------------+
//| HELPER: ĐỒNG BỘ SL THEO LỆNH MỚI NHẤT (KHÔNG TRAILING)           |
//+------------------------------------------------------------------+
void SyncAllStopLoss(bool isBuy, double newSL)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNum) continue;

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(isBuy && type != POSITION_TYPE_BUY)  continue;
      if(!isBuy && type != POSITION_TYPE_SELL) continue;

      double oldSL = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);

      // Nếu SL đã giống thì bỏ
      if(MathAbs(oldSL - newSL) < _Point) continue;

      if(!m_trade.PositionModify(ticket, newSL, tp))
      {
         PrintFormat(
            "❌ Sync SL FAIL | Ticket=%I64u | Ret=%d (%s)",
            ticket,
            m_trade.ResultRetcode(),
            m_trade.ResultRetcodeDescription()
         );
      }
      else
      {
         PrintFormat(
            "✅ Sync SL OK | Ticket=%I64u | New SL=%.2f",
            ticket, newSL
         );
      }
   }
}


//+------------------------------------------------------------------+
//| HELPER: Lọc thời gian bot chạy                           |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   if(!InpUseTimeFilter) return true; // Nếu không dùng thì luôn cho phép

   // 1. Lấy thời gian hiện tại của máy tính (Local Time - Giả định máy bạn để giờ VN)
   // Hoặc dùng giờ Server rồi cộng chênh lệch. Cách chuẩn nhất là dùng TimeLocal()
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt); // Lấy giờ từ máy tính của bạn (thường là giờ VN)

   int currentTime = dt.hour * 60 + dt.min;
   int startTime = InpStartHourVT * 60 + InpStartMinuteVT;
   int endTime = InpEndHourVT * 60 + InpEndMinuteVT;

   if(startTime < endTime) 
   {
      return (currentTime >= startTime && currentTime < endTime);
   }
   else // Trường hợp chạy xuyên đêm (ví dụ từ 22h tối đến 2h sáng)
   {
      return (currentTime >= startTime || currentTime < endTime);
   }
}