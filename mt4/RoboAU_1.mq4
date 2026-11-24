#property strict
#property version "0.10"
#property description "RoboAU 1 analytical development build; no order execution"
input bool AllowLiveTrading=false;

bool EmaPair(const double &closes[], const int period, const int lookback,
             double &current, double &past)
{
   int n=ArraySize(closes);
   if(period<=0 || lookback<0 || n<period+lookback) return false;
   double value=0.0;
   for(int i=0;i<period;i++) value+=closes[i];
   value/=period;
   int pastIndex=n-1-lookback;
   if(pastIndex==period-1) past=value;
   double alpha=2.0/(period+1.0);
   for(int j=period;j<n;j++)
   {
      value=alpha*closes[j]+(1.0-alpha)*value;
      if(j==pastIndex) past=value;
   }
   current=value;
   return true;
}

bool WilderAtr(const double &highs[], const double &lows[],
               const double &closes[], const int period, double &value)
{
   int n=ArraySize(closes);
   if(period<=0 || n<period+1 || ArraySize(highs)!=n || ArraySize(lows)!=n)
      return false;
   double acc=0.0;
   for(int i=1;i<n;i++)
   {
      if(highs[i]<lows[i]) return false;
      double tr=MathMax(highs[i]-lows[i],
                MathMax(MathAbs(highs[i]-closes[i-1]),MathAbs(lows[i]-closes[i-1])));
      if(i<=period) acc+=tr;
      if(i==period) acc/=period;
      if(i>period) acc=(acc*(period-1)+tr)/period;
   }
   value=acc;
   return true;
}

int OnInit()
{
   if(Symbol()!="XAUUSD" || Period()!=PERIOD_M5) return INIT_FAILED;
   Print("RoboAU 1 development build: no order execution.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   // Intentionally non-executing until signal and risk acceptance.
}
