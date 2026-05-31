//+------------------------------------------------------------------+
//|                                                       AO-bot.mq5 |
//|                                          by Jarosław N. Rożyński |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.10"

#include <Trade\Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Parametry wejściowe                                              |
//+------------------------------------------------------------------+
input double LotSize      = 0.01;      // Wielkość pozycji
input double SarStep      = 0.05;      // SAR step
input double SarMaximum   = 0.30;      // SAR maximum
input ulong  MagicNumber  = 909001;    // Magic number EA
input int    DeviationPts = 20;        // Maksymalne odchylenie ceny w punktach

//+------------------------------------------------------------------+
//| Uchwyty indikatorów                                              |
//+------------------------------------------------------------------+
int handleAO  = INVALID_HANDLE;
int handleSAR = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Kontrola pracy tylko raz na nowej świecy                         |
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

   // Jeżeli już jest BUY, nic nie robimy.
   if(currentType == POSITION_TYPE_BUY)
      return;

   // Jeżeli jest SELL albo inne pozycje EA, zamykamy wszystko.
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

   // Jeżeli już jest SELL, nic nie robimy.
   if(currentType == POSITION_TYPE_SELL)
      return;

   // Jeżeli jest BUY albo inne pozycje EA, zamykamy wszystko.
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
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   PrintFormat("TERMINAL_TRADE_ALLOWED=%d MQL_TRADE_ALLOWED=%d ACCOUNT_TRADE_ALLOWED=%d",
            TerminalInfoInteger(TERMINAL_TRADE_ALLOWED),
            MQLInfoInteger(MQL_TRADE_ALLOWED),
            AccountInfoInteger(ACCOUNT_TRADE_ALLOWED));

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
   // Pracujemy tylko raz po pojawieniu się nowej świecy.
   // Dzięki temu świeca [1] jest już zamknięta.
   if(!IsNewBar())
      return;

   // Dynamiczne tablice są konieczne, żeby ArraySetAsSeries działało bez warningów.
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
   // ao[0]  - aktualna świeca, jeszcze niezakończona
   // ao[1]  - poprzednia zamknięta świeca
   // ao[2]  - świeca wcześniejsza
   //
   // sar[1] - SAR dla poprzedniej zamkniętej świecy
   // low[1] - minimum poprzedniej zamkniętej świecy
   // high[1]- maksimum poprzedniej zamkniętej świecy

   double AO_1  = ao[1];
   double AO_2  = ao[2];
   double SAR_1 = sar[1];

   double High_1 = high[1];
   double Low_1  = low[1];

   bool sarBelowCandle = SAR_1 < Low_1;
   bool sarAboveCandle = SAR_1 > High_1;

   bool aoGrowing = AO_1 > AO_2;
   bool aoFalling = AO_1 < AO_2;

   // Sygnał LONG:
   // poprzednia świeca zamknięta z SAR pod świecą
   // oraz AO[1] > AO[2]
   bool longSignal = sarBelowCandle && aoGrowing;

   // Sygnał SHORT:
   // poprzednia świeca zamknięta z SAR nad świecą
   // oraz AO[1] < AO[2]
   bool shortSignal = sarAboveCandle && aoFalling;

   PrintFormat("AO[1]=%.5f AO[2]=%.5f SAR[1]=%.5f Low[1]=%.5f High[1]=%.5f long=%d short=%d",
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
   }
   else if(shortSignal)
   {
      OpenShort();
   }
}
//+------------------------------------------------------------------+