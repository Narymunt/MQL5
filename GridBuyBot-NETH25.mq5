//+------------------------------------------------------------------+
//|                                            GridBuyOnlyBot.mq5     |
//|                        by Jaroslaw N. Rozyński                   |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade trade;
COrderInfo orderInfo;
CPositionInfo positionInfo;

// Parametry wejściowe
double GridStepPips = 50;
double TakeProfitAll = 50;
double LotSize = 0.1;
double minBuyPrice = 1000; // większa niż obecny max

// Zmienne globalne
double pip;

//+------------------------------------------------------------------+
int OnInit()
{
   pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   Print("Init OK!");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Sprawdź łączny profit wszystkich pozycji BUY
   double totalProfit = 0.0;
   bool hasBuy = false;
   bool sellALL = true; 
   
   if (PositionsTotal()>0)
      hasBuy = true;
   
   // sprawdź czy ktoraś pozycja ma wynik <TakeProfitAll

   if (hasBuy)
   {
      minBuyPrice = 1000;
      
      for (int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);

         // sprawdzamy czy mamy nowe minimum cenowe, ustalamy je na podstawie najniższej ceny z aktualnej listy
      
         if (minBuyPrice > PositionGetDouble(POSITION_PRICE_OPEN))
            minBuyPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      
         if (PositionGetDouble(POSITION_PROFIT)<TakeProfitAll)
            sellALL = false;
      }
   }

   if (hasBuy && sellALL)
   {
      for (int i = PositionsTotal()-1; i>=0; i--)
      {
         if (positionInfo.SelectByIndex(i))
         {
            trade.PositionClose(positionInfo.Ticket());
         }
      }   
      hasBuy = false;
   }     


   // Otwórz BUY jeśli nie ma żadnych lub ostatnia cena + GridStep
   double lastPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   Print("lastPrice ",lastPrice," - minBuyPrice ",minBuyPrice," = ", lastPrice-minBuyPrice," >= GridStepsPips ",GridStepPips);

   if (!hasBuy)
   {
      trade.Buy(1.0f, _Symbol, lastPrice, 0, lastPrice+GridStepPips, "First Grid BUY");
      hasBuy = true;
      return;
   }
   
   if ((lastPrice - minBuyPrice) < -GridStepPips)
   {
      trade.Buy(1.0f, _Symbol, lastPrice, 0, lastPrice+GridStepPips, "Next Grid BUY");
      hasBuy = true;
   }
}
//+------------------------------------------------------------------+
