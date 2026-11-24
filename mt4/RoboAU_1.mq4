#property strict
#property version "0.20"
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

struct Bar
{
   datetime time;
   double o,h,l,c;
};
struct Setup
{
   int direction;
   datetime breakout,retest,continuation,confirmation;
   double level,stop;
};
bool LoadBars(const int tf,const int n,Bar &bars[])
{
   if(iBars(Symbol(),tf)<n+1) return false;
   ArrayResize(bars,n);
   for(int i=0;i<n;i++)
   {
      int shift=n-i;
      bars[i].time=iTime(Symbol(),tf,shift);
      bars[i].o=iOpen(Symbol(),tf,shift);
      bars[i].h=iHigh(Symbol(),tf,shift);
      bars[i].l=iLow(Symbol(),tf,shift);
      bars[i].c=iClose(Symbol(),tf,shift);
      if(bars[i].time<=0 || bars[i].l<=0 || bars[i].h<bars[i].l ||
         bars[i].o<bars[i].l || bars[i].o>bars[i].h ||
         bars[i].c<bars[i].l || bars[i].c>bars[i].h ||
         (i>0 && bars[i].time<=bars[i-1].time)) return false;
   }
   return true;
}
int Direction(const Bar &bars[])
{
   if(ArraySize(bars)!=60) return 0;
   double closes[];
   ArrayResize(closes,60);
   for(int i=0;i<60;i++) closes[i]=bars[i].c;
   double fast=0,past=0,slow=0,unused=0;
   if(!EmaPair(closes,20,5,fast,past) || !EmaPair(closes,50,5,slow,unused)) return 0;
   if(closes[59]>fast && fast>slow && fast>past) return 1;
   if(closes[59]<fast && fast<slow && fast<past) return -1;
   return 0;
}
bool AtrPrefix(const Bar &bars[],const int end,double &atr)
{
   if(end<14 || end>=ArraySize(bars)) return false;
   double h[],l[],c[];
   ArrayResize(h,end+1); ArrayResize(l,end+1); ArrayResize(c,end+1);
   for(int i=0;i<=end;i++){h[i]=bars[i].h;l[i]=bars[i].l;c[i]=bars[i].c;}
   return WilderAtr(h,l,c,14,atr);
}
bool Structure(const Bar &b[],const int dir,Setup &s)
{
   if(ArraySize(b)!=200 || (dir!=1 && dir!=-1)) return false;
   int last=199;
   for(int j=last-2;j>=188;j--)
   {
      double atr=0;
      if(!AtrPrefix(b,j,atr) || atr<=0) continue;
      double level=(dir==1?b[j-20].h:b[j-20].l);
      for(int k=j-19;k<j;k++)
         level=(dir==1?MathMax(level,b[k].h):MathMin(level,b[k].l));
      if(dir==1 && !(b[j].c>level+0.10*atr && b[j].c>b[j].o)) continue;
      if(dir==-1 && !(b[j].c<level-0.10*atr && b[j].c<b[j].o)) continue;
      double tolerance=0.15*atr;
      int selected=-1;
      int end=j+6;
      if(end>last-1) end=last-1;
      for(int q=end;q>j;q--)
      {
         double extreme=(dir==1?b[q].l:b[q].h);
         if(extreme>=level-tolerance && extreme<=level+tolerance &&
            (dir==1?b[q].c>level:b[q].c<level))
         {selected=q;break;}
      }
      if(selected<0) continue;
      if(dir==1 && !(b[last].c>b[selected].h && b[last].c>b[last].o && b[last].c>level)) continue;
      if(dir==-1 && !(b[last].c<b[selected].l && b[last].c<b[last].o && b[last].c<level)) continue;
      double ca=0;
      if(!AtrPrefix(b,last,ca) || ca<=0) continue;
      s.direction=dir;s.breakout=b[j].time;s.retest=b[selected].time;
      s.continuation=b[last].time;s.level=level;
      s.stop=(dir==1?b[selected].l-0.10*ca:b[selected].h+0.10*ca);
      return true;
   }
   return false;
}
bool Confirm(const Bar &b[],Setup &s)
{
   if(ArraySize(b)!=300 || (s.direction!=1 && s.direction!=-1)) return false;
   int i=299;
   if(b[i].time<s.continuation+3600) return false;
   double range=b[i].h-b[i].l;
   if(range<=0) return false;
   double location=(b[i].c-b[i].l)/range;
   double level=(s.direction==1?b[i-5].h:b[i-5].l);
   for(int j=i-4;j<i;j++)
      level=(s.direction==1?MathMax(level,b[j].h):MathMin(level,b[j].l));
   if(s.direction==1 && !(b[i].c>level && b[i].c>b[i].o && location>=0.70)) return false;
   if(s.direction==-1 && !(b[i].c<level && b[i].c<b[i].o && location<=0.30)) return false;
   s.confirmation=b[i].time;
   return true;
}
datetime lastBar=0;
string lastSetup="";
int OnInit()
{
   if(Symbol()!="XAUUSD" || Period()!=PERIOD_M5) return INIT_FAILED;
   lastBar=iTime(Symbol(),PERIOD_M5,0);
   Print("RoboAU 1 signal-only development build: no order execution.");
   return INIT_SUCCEEDED;
}
void OnTick()
{
   datetime now=iTime(Symbol(),PERIOD_M5,0);
   if(now<=0 || now<=lastBar) return;
   Bar d[],h[],m[];
   if(!LoadBars(PERIOD_D1,60,d) || !LoadBars(PERIOD_H1,200,h) ||
      !LoadBars(PERIOD_M5,300,m)) return;
   // Avoid a mixed snapshot if a new M5 bar appeared while reading.
   if(iTime(Symbol(),PERIOD_M5,0)!=now) return;
   lastBar=now;
   int dir=Direction(d);
   Setup s;
   if(dir==0 || !Structure(h,dir,s) || !Confirm(m,s)) return;
   string key=Symbol()+"|"+IntegerToString(dir)+"|"+IntegerToString((long)s.breakout)
      +"|"+IntegerToString((long)s.retest)+"|"+IntegerToString((long)s.continuation);
   if(key==lastSetup) return;
   lastSetup=key;
   Print("CANDIDATE_ONLY ",key," confirmation=",TimeToString(s.confirmation),
         " SL=",DoubleToString(s.stop,Digits));
}
