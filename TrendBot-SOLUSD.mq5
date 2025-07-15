//+------------------------------------------------------------------+
//|                                            TrendBotStrategy.mq5  |
//|                        by Jarosław N. Rożyński                   |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Parametry wejściowe
input double StartLot = 2.0;
input double TakeProfitPips = 25;
input double StopLossPips = 25;

// Zmienne globalne
double currentLot = 1.0f;
bool isLong = true;
bool isPositionOpen = false;
ulong globalTicket = 0;
double previousBalance = 0.0;

//+------------------------------------------------------------------+
int OnInit()
{
   previousBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("Init OK!");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Sprawdzenie czy pozycja jest otwarta
   if (!isPositionOpen)
   {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      if (globalTicket != 0)
      {
         double profit = currentBalance - previousBalance;
         Print("Zamknięty zysk/strata: ", profit);

         if (profit < 0)
         {
            currentLot = currentLot;// +1; //+= 0.01;
            isLong = !isLong;
            Print("Strata. Zmieniamy kierunek i zwiększamy lot: ", DoubleToString(currentLot, 2));
         }
         else if (profit > 0)
         {
            currentLot -= 1;
            if (currentLot < 1)
               currentLot = 1;
            Print("Zysk. Zmniejszamy lot, kierunek bez zmian: ", DoubleToString(currentLot, 2));
         }
         previousBalance = currentBalance;
      }
      
      //currentLot = 1.0f;
      Print("START: Aktualny lot przed otwarciem: ", DoubleToString(currentLot, 2));
      globalTicket = OpenTrade();
      if (globalTicket > 0)
         isPositionOpen = true;
   }
   else
   {
      if (!PositionSelectByTicket(globalTicket))
         isPositionOpen = false;
   }
}

//+------------------------------------------------------------------+
ulong OpenTrade()
{
   double price = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0.0, tp = 0.0;
   double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) *100;
   double slPips = StopLossPips * pip;
   double tpPips = slPips; //TakeProfitPips * pip;

   if (isLong)
   {
      sl = price - slPips;
      tp = price + tpPips;
      if (!trade.Buy(currentLot, _Symbol, price, price-1, price+1, "Long Entry"))
      {
         Print("Błąd otwierania pozycji LONG: ", trade.ResultRetcode(), ", komentarz: ", trade.ResultComment());
         return 0;
      }
   }
   else
   {
      sl = price + slPips;
      tp = price - tpPips;
      if (!trade.Sell(currentLot, _Symbol, price, price+1, price-1, "Short Entry"))
      {
         Print("Błąd otwierania pozycji SHORT: ", trade.ResultRetcode(), ", komentarz: ", trade.ResultComment());
         return 0;
      }
   }

   return trade.ResultOrder();
}
//+------------------------------------------------------------------+
