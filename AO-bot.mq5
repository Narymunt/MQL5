//+------------------------------------------------------------------+
//|                                                       AO-bot.mq5 |
//|                                          by Jarosław N. Rożyński |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

CTrade trade;

bool isEmpty = true;

input double value = 0.01;

bool shortPosition = false;
bool longPosition = false;
int handleAO = iAO(_Symbol, _Period);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   handleAO = iAO(_Symbol, _Period);
   
   Print ("Init OK!");
   
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   double aoValues[3];

   if (CopyBuffer(handleAO, 0, 0, 3, aoValues)>0)
   {

      // aoValues[3] - aktualna wartość
      double AO0 = aoValues[1]; // ostatnia zamknieta wartość AO 
      double AO1 = aoValues[0]; // przedostatnia
      
      //PrintFormat("[0]: %.2f [1]: %.2f [2]: %.2f",aoValues[0],aoValues[1],aoValues[2]);      
      
      if (isEmpty)
      {
         if (AO0 < AO1)
         {
            PrintFormat("%.2f < %.2f SELL %s", AO0, AO1, _Symbol);
         
            trade.Sell(value, _Symbol);
            isEmpty = false;
            shortPosition = true;
            longPosition = false;
         }
         else if (AO0 > AO1)
         {
            PrintFormat("%.2f > %.2f BUY %s", AO0, AO1, _Symbol);
            trade.Buy(value, _Symbol);
            isEmpty = false;
            shortPosition = false;
            longPosition = true;
         }
      }
      else if (!isEmpty && shortPosition)
      {
         if (AO0 > AO1)
         {
            trade.PositionClose(_Symbol);
            isEmpty = true;
            shortPosition = false;
         }
      }
      else if (!isEmpty && longPosition)
      {
         if (AO0<AO1)
         {
            trade.PositionClose(_Symbol);
            isEmpty = true;
            longPosition = false;
         }
      }
   }
   else 
   {
      Print("Nie można odczytać AO z bufora!");
   }
}
//+------------------------------------------------------------------+
