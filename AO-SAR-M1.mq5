//+------------------------------------------------------------------+
//|                                                       AO-bot.mq5 |
//|                                          by Jarosław N. Rożyński |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.12"

#include <Trade\Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Parametry wejściowe                                              |
//+------------------------------------------------------------------+
input double LotSize      = 0.01;      // Wielkość pozycji
input double SarStep      = 0.05;      // SAR step
input double SarMaximum   = 0.30;      // SAR maximum
input ulong  MagicNumber  = 909001;    // Magic number EA
input int    DeviationPts = 20;        // Maksymalny poślizg ceny w punktach

//+------------------------------------------------------------------+
//| Uchwyty indikatorów                                              |
//+------------------------------------------------------------------+
int handleAO  = INVALID_HANDLE;
int handleSAR = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Kontrola pracy logiki wejścia tylko raz na nowej świecy          |
//+------------------------------------------------------------------+
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Sprawdzenie, czy pojawiła się nowa świeca                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);

   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Pobranie aktualnego typu pozycji EA na danym symbolu             |
//| Zwraca: POSITION_TYPE_BUY, POSITION_TYPE_SELL albo -1            |
//+------------------------------------------------------------------+
int GetCurrentPositionType()
{
   int foundType = -1;
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic   = (ulong)PositionGetInteger(POSITION_MAGIC);

      if(symbol == _Symbol && magic == MagicNumber)
      {
         foundType = (int)PositionGetInteger(POSITION_TYPE);
         count++;
      }
   }

   if(count > 1)
   {
      PrintFormat("UWAGA: wykryto %d pozycji EA na symbolu %s", count, _Symbol);
   }

   return foundType;
}

//+------------------------------------------------------------------+
//| Zamknięcie wszystkich pozycji EA na aktualnym symbolu            |
//+------------------------------------------------------------------+
bool CloseAllPositionsForSymbol()
{
   bool result = true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic   = (ulong)PositionGetInteger(POSITION_MAGIC);

      if(symbol == _Symbol && magic == MagicNumber)
      {
         if(!trade.PositionClose(ticket))
         {
            PrintFormat("Błąd zamykania pozycji ticket=%I64u, retcode=%d",
                        ticket,
                        trade.ResultRetcode());
            result = false;
         }
         else
         {
            PrintFormat("Zamknięto pozycję ticket=%I64u", ticket);
         }
      }
   }

   return result;
}

//+------------------------------------------------------------------+
//| Otwarcie pozycji LONG                                            |
//+------------------------------------------------------------------+
void OpenLong()
{
   int currentType = GetCurrentPositionType();

   if(currentType == POSITION_TYPE_BUY)
      return;

   if(!CloseAllPositionsForSymbol())
   {
      Print("Nie udało się zamknąć wszystkich pozycji przed otwarciem BUY.");
      return;
   }

   if(trade.Buy(LotSize, _Symbol))
   {
      PrintFormat("BUY %s lot=%.2f", _Symbol, LotSize);
   }
   else
   {
      PrintFormat("Błąd BUY %s, retcode=%d", _Symbol, trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Otwarcie pozycji SHORT                                           |
//+------------------------------------------------------------------+
void OpenShort()
{
   int currentType = GetCurrentPositionType();

   if(currentType == POSITION_TYPE_SELL)
      return;

   if(!CloseAllPositionsForSymbol())
   {
      Print("Nie udało się zamknąć wszystkich pozycji przed otwarciem SELL.");
      return;
   }

   if(trade.Sell(LotSize, _Symbol))
   {
      PrintFormat("SELL %s lot=%.2f", _Symbol, LotSize);
   }
   else
   {
      PrintFormat("Błąd SELL %s, retcode=%d", _Symbol, trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Tickowe zamknięcie pozycji po aktualnym SAR[0]                   |
//+------------------------------------------------------------------+
bool CheckCurrentSarExit()
{
   int currentType = GetCurrentPositionType();

   if(currentType != POSITION_TYPE_BUY && currentType != POSITION_TYPE_SELL)
      return false;

   double sarNow[];

   ArrayResize(sarNow, 1);

   if(CopyBuffer(handleSAR, 0, 0, 1, sarNow) <= 0)
   {
      Print("Nie można odczytać aktualnego SAR[0]!");
      return false;
   }

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Nie można odczytać aktualnego ticka!");
      return false;
   }

   double SAR_0 = sarNow[0];

   // Dla LONG zamykamy pozycję, gdy aktualny SAR pojawił się nad bieżącą ceną.
   // Zamknięcie LONG odbywa się po BID, więc porównujemy z tick.bid.
   bool closeLongByCurrentSar =
      currentType == POSITION_TYPE_BUY &&
      SAR_0 > tick.bid;

   // Dla SHORT zamykamy pozycję, gdy aktualny SAR pojawił się pod bieżącą ceną.
   // Zamknięcie SHORT odbywa się po ASK, więc porównujemy z tick.ask.
   bool closeShortByCurrentSar =
      currentType == POSITION_TYPE_SELL &&
      SAR_0 < tick.ask;

   if(closeLongByCurrentSar)
   {
      PrintFormat("TICK EXIT LONG: SAR[0]=%.5f > BID=%.5f", SAR_0, tick.bid);
      CloseAllPositionsForSymbol();
      return true;
   }

   if(closeShortByCurrentSar)
   {
      PrintFormat("TICK EXIT SHORT: SAR[0]=%.5f < ASK=%.5f", SAR_0, tick.ask);
      CloseAllPositionsForSymbol();
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPts);

   handleAO = iAO(_Symbol, _Period);

   if(handleAO == INVALID_HANDLE)
   {
      Print("Błąd tworzenia handle AO!");
      return INIT_FAILED;
   }

   handleSAR = iSAR(_Symbol, _Period, SarStep, SarMaximum);

   if(handleSAR == INVALID_HANDLE)
   {
      Print("Błąd tworzenia handle SAR!");
      return INIT_FAILED;
   }

   Print("Init OK!");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleAO != INVALID_HANDLE)
      IndicatorRelease(handleAO);

   if(handleSAR != INVALID_HANDLE)
      IndicatorRelease(handleSAR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Priorytet 1:
   // Zamknięcie po aktualnym SAR[0] działa CO TICK.
   // Nie czekamy na zamknięcie świecy.
   if(CheckCurrentSarExit())
      return;

   // Priorytet 2:
   // Wejścia / odwrócenia pozycji robimy tylko raz na nowej świecy,
   // ponieważ AO[1] i AO[2] muszą pochodzić z zamkniętych świec.
   if(!IsNewBar())
      return;

   double ao[];
   double sar[];
   double high[];
   double low[];

   ArrayResize(ao, 3);
   ArrayResize(sar, 3);
   ArrayResize(high, 3);
   ArrayResize(low, 3);

   ArraySetAsSeries(ao, true);
   ArraySetAsSeries(sar, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(CopyBuffer(handleAO, 0, 0, 3, ao) <= 0)
   {
      Print("Nie można odczytać AO z bufora!");
      return;
   }

   if(CopyBuffer(handleSAR, 0, 0, 3, sar) <= 0)
   {
      Print("Nie można odczytać SAR z bufora!");
      return;
   }

   if(CopyHigh(_Symbol, _Period, 0, 3, high) <= 0)
   {
      Print("Nie można odczytać High!");
      return;
   }

   if(CopyLow(_Symbol, _Period, 0, 3, low) <= 0)
   {
      Print("Nie można odczytać Low!");
      return;
   }

   // Indeksy po ArraySetAsSeries(..., true):
   //
   // ao[0]   - aktualna świeca, jeszcze niezakończona
   // ao[1]   - poprzednia zamknięta świeca
   // ao[2]   - świeca wcześniejsza
   //
   // sar[0]  - aktualny SAR na bieżącej świecy
   // sar[1]  - SAR poprzedniej zamkniętej świecy

   double AO_1  = ao[1];
   double AO_2  = ao[2];
   double SAR_1 = sar[1];

   double High_1 = high[1];
   double Low_1  = low[1];

   bool sarBelowClosedCandle = SAR_1 < Low_1;
   bool sarAboveClosedCandle = SAR_1 > High_1;

   bool aoGrowing = AO_1 > AO_2;
   bool aoFalling = AO_1 < AO_2;

   bool longSignal  = sarBelowClosedCandle && aoGrowing;
   bool shortSignal = sarAboveClosedCandle && aoFalling;

   PrintFormat("ENTRY CHECK: AO[1]=%.5f AO[2]=%.5f SAR[1]=%.5f Low[1]=%.5f High[1]=%.5f long=%d short=%d",
               AO_1,
               AO_2,
               SAR_1,
               Low_1,
               High_1,
               longSignal,
               shortSignal);

   if(longSignal)
   {
      OpenLong();
      return;
   }

   if(shortSignal)
   {
      OpenShort();
      return;
   }
}
//+------------------------------------------------------------------+