#property strict
#property version "0.950"
#property description "RoboAU 1 execution candidate; release locked"
input bool AllowLiveTrading=false;
input bool EnableTrading=false;
input int MagicNumber=710001;
input int MaxSlippagePoints=0;
input double TradeRiskPercent=5.0;
input double DailyRiskPercent=10.0;
input double AggregateRiskPercent=10.0;
input double MaximumStopDistance=50.0;
// Owner-configured broker server wall-clock times, HH:MM.
input string FridayCloseTime="21:15";
input string MondayOpenTime="00:00";
int fridayCloseMinutes=-1, mondayOpenMinutes=-1;
bool ParseClock(const string value,int &minutes)
{
   if(StringLen(value)!=5 || StringGetCharacter(value,2)!=58) return false;
   for(int i=0;i<5;i++)
   {
      if(i==2) continue;
      ushort c=StringGetCharacter(value,i);
      if(c<48 || c>57) return false;
   }
   int h=(int)StringToInteger(StringSubstr(value,0,2));
   int m=(int)StringToInteger(StringSubstr(value,3,2));
   if(h>23 || m>59) return false;
   minutes=h*60+m;
   return true;
}
// Source-level release lock. Removed only after acceptance.
const bool ExecutionReleaseAccepted=false;

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
// Pure planning functions. No broker dispatch in this increment.
struct TradePlan
{
   double entry,stop,target,lots,riskMoney;
};
bool BuildPlan(const int dir,const double entry,const double rawStop,
               const double tickSize,const double tickValue,
               const double minLot,const double maxLot,const double lotStep,
               const double budget,const double extraCostPerLot,
               TradePlan &p)
{
   if((dir!=1 && dir!=-1) || !MathIsValidNumber(entry) ||
      !MathIsValidNumber(rawStop) || !MathIsValidNumber(tickSize) ||
      !MathIsValidNumber(tickValue) || !MathIsValidNumber(minLot) ||
      !MathIsValidNumber(maxLot) || !MathIsValidNumber(lotStep) ||
      !MathIsValidNumber(budget) || !MathIsValidNumber(extraCostPerLot) ||
      entry<=0 || rawStop<=0 || tickSize<=0 || tickValue<=0 ||
      minLot<=0 || maxLot<minLot || lotStep<=0 || budget<=0 || extraCostPerLot<0)
      return false;
   // Round the structural stop away from entry, never toward it.
   double stop=(dir==1?MathFloor(rawStop/tickSize):MathCeil(rawStop/tickSize))*tickSize;
   double distance=dir*(entry-stop);
   if(distance<=0 || stop<=0 || distance>MaximumStopDistance) return false;
   double target=entry+dir*3.0*distance;
   if(target<=0 || !MathIsValidNumber(target)) return false;
   double lossPerLot=distance/tickSize*tickValue+extraCostPerLot;
   if(lossPerLot<=0 || !MathIsValidNumber(lossPerLot)) return false;
   double cap=MathMin(maxLot,budget/lossPerLot);
   if(cap<minLot) return false;
   double lots=NormalizeDouble(MathFloor(cap/lotStep)*lotStep,8);
   if(lots*lossPerLot>budget || lots>maxLot)
      lots=NormalizeDouble(lots-lotStep,8);
   if(lots<minLot || lots*lossPerLot>budget || lots>maxLot) return false;
   p.entry=entry;p.stop=stop;p.target=target;p.lots=lots;
   p.riskMoney=lots*lossPerLot;
   return true;
}
double AvailableBudget(const double equity,const double dayBase,
                       const double realizedLoss,const double openRisk)
{
   if(!MathIsValidNumber(equity)||!MathIsValidNumber(dayBase)||
      !MathIsValidNumber(realizedLoss)||!MathIsValidNumber(openRisk)||
      equity<=0 || dayBase<=0 || realizedLoss<0 || openRisk<0) return 0;
   return MathMax(0.0,MathMin(TradeRiskPercent/100.0*equity,
             MathMin(DailyRiskPercent/100.0*dayBase-realizedLoss-openRisk,AggregateRiskPercent/100.0*equity-openRisk)));
}
bool AccountModeAllowed()
{
   long mode=AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(mode==ACCOUNT_TRADE_MODE_DEMO) return true;
   return mode==ACCOUNT_TRADE_MODE_REAL && AllowLiveTrading;
}
int instanceLock=INVALID_HANDLE;
datetime lastBar=0;
string lastSetup="";
// A separate, exclusive journal per account/server/symbol.
// No FILE_SHARE_WRITE: simultaneous instances fail closed.
string JournalName()
{
   string server=AccountServer();
   StringReplace(server,"/","_"); StringReplace(server,"\\","_");
   StringReplace(server,":","_"); StringReplace(server,"*","_");
   StringReplace(server,"?","_"); StringReplace(server,"|","_");
   StringReplace(server,"\"","_"); StringReplace(server,"<","_");
   StringReplace(server,">","_");
   return "RoboAU1_"+server+"_"+IntegerToString(AccountNumber())+
          "_"+Symbol()+(IsTesting()?"_tester":"_terminal")+".csv";
}
bool ReserveSignal(const string key,const Setup &s)
{
   int f=FileOpen(JournalName(),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(f==INVALID_HANDLE){Print("JOURNAL_OPEN_FAILED ",GetLastError());return false;}
   while(!FileIsEnding(f))
   {
      string seen=FileReadString(f);
      while(!FileIsLineEnding(f) && !FileIsEnding(f)) FileReadString(f);
      if(seen==key){FileClose(f);return false;}
   }
   if(!FileSeek(f,0,SEEK_END)){FileClose(f);return false;}
   uint written=FileWrite(f,key,"CANDIDATE",TimeToString(s.confirmation,TIME_DATE|TIME_SECONDS),
                          DoubleToString(s.stop,Digits));
   FileFlush(f);
   FileClose(f);
   return written>0;
}
// Use available closed trades today; no audit of full account history.
// If daily data are unavailable, skip only the daily limit.
bool ReadAccountRisk(double &balance,double &equity,double &margin,
                     double &dayBase,double &loss,double &openRisk,bool &dailyAvailable)
{
   balance=AccountBalance(); equity=AccountEquity(); margin=AccountFreeMargin();
   dayBase=balance; loss=0; openRisk=0;
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(balance<=0 || equity<=0 || margin<=0) return false;
   dailyAvailable=(today>0 && OrdersHistoryTotal()>0);
   int historyCount=OrdersHistoryTotal();
   for(int i=0;i<historyCount && dailyAvailable;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)){dailyAvailable=false;break;}
      if(OrderCloseTime()<today) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL)
      {
         if(type>OP_SELLSTOP){dailyAvailable=false;break;}
         continue;
      }
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      if(!MathIsValidNumber(net)){dailyAvailable=false;break;}
      dayBase-=net;
      loss+=MathMax(0.0,-net);
   }
   if(dayBase<=0 || !MathIsValidNumber(dayBase) || OrdersHistoryTotal()!=historyCount)
      dailyAvailable=false;
   if(!dailyAvailable){dayBase=0;loss=0;}
   for(int j=0;j<OrdersTotal();j++)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) return false;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) return false;
      string sym=OrderSymbol();
      double ts=MarketInfo(sym,MODE_TICKSIZE),tv=MarketInfo(sym,MODE_TICKVALUE);
      double mark=MarketInfo(sym,type==OP_BUY?MODE_BID:MODE_ASK);
      double stop=OrderStopLoss();
      if(ts<=0 || tv<=0 || mark<=0 || stop<=0 || OrderLots()<=0) return false;
      double distance=(type==OP_BUY?mark-stop:stop-mark);
      if(distance<=0) return false;
      openRisk+=distance/ts*tv*OrderLots();
   }
   return MathIsValidNumber(openRisk);
}
input double EstimatedRoundTripCostPerLot=-1.0;
bool BrokerPlan(const Setup &s,TradePlan &p,string &reason)
{
   if(!AccountModeAllowed()){reason="ACCOUNT_MODE";return false;}
   if(EstimatedRoundTripCostPerLot<0){reason="COST_NOT_CONFIGURED";return false;}
   double bal,eq,margin,base,loss,risk;
   bool dailyAvailable=false;
   if(!ReadAccountRisk(bal,eq,margin,base,loss,risk,dailyAvailable))
   {reason="ACCOUNT_RISK_UNVERIFIED";return false;}
   double budget=0;
   if(dailyAvailable) budget=AvailableBudget(eq,base,loss,risk);
   else
   {
      budget=MathMax(0.0,MathMin(TradeRiskPercent/100.0*eq,AggregateRiskPercent/100.0*eq-risk));
      Print("DAILY_RISK_UNAVAILABLE: using trade and aggregate limits only");
   }
   RefreshRates();
   double entry=(s.direction==1?Ask:Bid);
   double ts=MarketInfo(Symbol(),MODE_TICKSIZE),tv=MarketInfo(Symbol(),MODE_TICKVALUE);
   if(!BuildPlan(s.direction,entry,s.stop,ts,tv,
      MarketInfo(Symbol(),MODE_MINLOT),MarketInfo(Symbol(),MODE_MAXLOT),
      MarketInfo(Symbol(),MODE_LOTSTEP),budget,EstimatedRoundTripCostPerLot,p))
   {reason="PLAN_REJECTED";return false;}
   double minDistance=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   double mark=(s.direction==1?Bid:Ask);
   if(s.direction*(mark-p.stop)<=minDistance ||
      s.direction*(p.target-mark)<=minDistance)
   {reason="BROKER_STOP_DISTANCE";return false;}
   ResetLastError();
   double remaining=AccountFreeMarginCheck(Symbol(),s.direction==1?OP_BUY:OP_SELL,p.lots);
   if(remaining<=0 || GetLastError()!=0){reason="MARGIN";return false;}
   reason="PLAN_ONLY";return true;
}
// Broker execution candidate. Never called against a live terminal by
// this development release; tester execution requires explicit enable.
// Persistent fail-closed marker: retained across restart after any uncertain
// submission or failed verification. Never automatically clear it.
string RecoveryFile(){return JournalName()+".recovery";}
bool RecoveryBlocked(){return FileIsExist(RecoveryFile());}
bool BeginRecovery(const string key)
{
   if(RecoveryBlocked()) return false;
   int f=FileOpen(RecoveryFile(),FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE) return false;
   uint n=FileWriteString(f,key+"\r\n");
   FileFlush(f);FileClose(f);
   return n>0 && FileIsExist(RecoveryFile());
}
// Read-only reconciliation: report known broker positions and protection
// after restart. Unknown submissions remain locked; absence of an order
// in the locally loaded history is not proof of non-execution.
void ReconcileBrokerState()
{
   int active=0,history=0,invalid=0,missing=0;
   for(int i=0;i<OrdersTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
      {invalid++;continue;}
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      active++;
      int type=OrderType();
      double entry=OrderOpenPrice(),sl=OrderStopLoss(),tp=OrderTakeProfit();
      int dir=(type==OP_BUY?1:type==OP_SELL?-1:0);
      double risk=dir*(entry-sl);
      if(dir==0 || sl<=0 || tp<=0 || risk<=0 ||
         MathAbs(tp-(entry+dir*3.0*risk))>Point*0.51) invalid++;
      if(!FileIsExist(JournalName()+".fill_"+IntegerToString(OrderTicket())+".csv")) missing++;
      Print("RECOVERY_OPEN ticket=",OrderTicket()," type=",type,
            " lots=",OrderLots()," SL=",sl," TP=",tp);
   }
   for(int j=0;j<OrdersHistoryTotal();j++)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_HISTORY))
      {invalid++;continue;}
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber &&
         (OrderType()==OP_BUY || OrderType()==OP_SELL)) history++;
   }
   Print("RECOVERY_SUMMARY active=",active," loaded_closed=",history,
         " invalid=",invalid," missing_fill=",missing," marker=",RecoveryBlocked());
   if((invalid>0 || missing>0) && !RecoveryBlocked())
      BeginRecovery("RESTART_BROKER_STATE_UNVERIFIED");
}
bool ExecutionAllowed()
{
   if(RecoveryBlocked()) return false;
   if(!EnableTrading || !AccountModeAllowed()) return false;
   if(IsTesting()) return true;
   return ExecutionReleaseAccepted && IsTradeAllowed();
}
void EventLog(const string key,const string status,const string detail)
{
   Print("ROBOAU ",key," ",status," ",detail);
   int f=FileOpen(JournalName()+".events.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(f==INVALID_HANDLE){Print("EVENT_LOG_FAILED ",GetLastError());return;}
   if(FileSeek(f,0,SEEK_END))
      FileWrite(f,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),key,status,detail);
   FileFlush(f);FileClose(f);
}
// Persist initial risk and execution prices by ticket, without overwriting
// an existing record. Missing records are excluded from R statistics.
string FillFile(const int ticket)
{
   return JournalName()+".fill_"+IntegerToString(ticket)+".csv";
}
bool SaveFill(const int ticket,const string key,const double requested,
              const double fill,const double spread,const double risk,
              const int direction)
{
   string name=FillFile(ticket);
   if(FileIsExist(name)) return false;
   int f=FileOpen(name,FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(f==INVALID_HANDLE) return false;
   uint n=FileWrite(f,key,ticket,DoubleToString(requested,Digits),
      DoubleToString(fill,Digits),DoubleToString(spread,Digits),
      DoubleToString(direction*(fill-requested),Digits),
      DoubleToString(risk,10));
   FileFlush(f);FileClose(f);
   return n>0;
}
bool ReadFillRisk(const int ticket,double &risk)
{
   int f=FileOpen(FillFile(ticket),FILE_READ|FILE_CSV|FILE_ANSI,';');
   if(f==INVALID_HANDLE) return false;
   string key=FileReadString(f);
   int stored=(int)FileReadNumber(f);
   double requested=FileReadNumber(f);
   double fill=FileReadNumber(f);
   double spread=FileReadNumber(f);
   double slip=FileReadNumber(f);
   risk=FileReadNumber(f);
   FileClose(f);
   return StringLen(key)>0 && stored==ticket && requested>0 && fill>0 &&
      spread>=0 && MathIsValidNumber(slip) &&
      MathIsValidNumber(risk) && risk>0;
}
bool DispatchCandidate(const string key,const Setup &s)
{
   if(!ExecutionAllowed()){EventLog(key,"BLOCKED","EXECUTION_GATE");return false;}
   TradePlan p; string reason="";
   if(!BrokerPlan(s,p,reason)){EventLog(key,"REJECTED",reason);return false;}
   // A persistent reservation was written before this function.
   // Never retry an uncertain submission automatically.
   int type=(s.direction==1?OP_BUY:OP_SELL);
   double entry=NormalizeDouble(p.entry,Digits);
   double stop=NormalizeDouble(p.stop,Digits);
   double target=NormalizeDouble(p.target,Digits);
   if(!ExecutionAllowed()){EventLog(key,"BLOCKED","MODE_CHANGED");return false;}
   double requestedSpread=Ask-Bid;
   if(requestedSpread<0 || !MathIsValidNumber(requestedSpread)) return false;
   if(!BeginRecovery(key)){EventLog(key,"BLOCKED","RECOVERY_MARKER");return false;}
   ResetLastError();
   int ticket=OrderSend(Symbol(),type,p.lots,entry,MaxSlippagePoints,
                        stop,target,"RoboAU1",MagicNumber,0,clrNONE);
   int err=GetLastError();
   if(ticket<0){EventLog(key,"SUBMISSION_FAILED",IntegerToString(err));return false;}
   EventLog(key,"TICKET",IntegerToString(ticket));
   if(!OrderSelect(ticket,SELECT_BY_TICKET))
   {EventLog(key,"RECONCILIATION_REQUIRED","SELECT_FAILED");return false;}
   if(OrderCloseTime()!=0)
   {EventLog(key,"RECONCILIATION_REQUIRED","ALREADY_CLOSED");return false;}
   double fill=OrderOpenPrice();
   double actualStop=OrderStopLoss();
   double actualR=s.direction*(fill-actualStop);
   if(actualStop<=0 || actualR<=0 || actualR>MaximumStopDistance)
   {EventLog(key,"RECONCILIATION_REQUIRED","STOP_INVALID");return false;}
   double ts=MarketInfo(Symbol(),MODE_TICKSIZE),tv=MarketInfo(Symbol(),MODE_TICKVALUE);
   if(ts<=0 || tv<=0 || OrderLots()<=0 || OrderSymbol()!=Symbol() ||
      OrderMagicNumber()!=MagicNumber || OrderType()!=type ||
      MathAbs(actualStop-stop)>Point*0.1)
   {EventLog(key,"RECONCILIATION_REQUIRED","FILL_IDENTITY_OR_STOP");return false;}
   double actualRisk=OrderLots()*(actualR/ts*tv+EstimatedRoundTripCostPerLot);
   if(!MathIsValidNumber(actualRisk) || actualRisk>p.riskMoney+0.000001)
   {EventLog(key,"RECONCILIATION_REQUIRED","FILL_RISK_EXCEEDED");return false;}
   if(!SaveFill(ticket,key,entry,fill,requestedSpread,actualRisk,s.direction))
   {EventLog(key,"RECONCILIATION_REQUIRED","FILL_RECORD_FAILED");return false;}
   double tp=NormalizeDouble(fill+s.direction*3.0*actualR,Digits);
   if(tp<=0){EventLog(key,"RECONCILIATION_REQUIRED","TARGET_INVALID");return false;}
   if(MathAbs(OrderTakeProfit()-tp)>Point*0.1)
   {
      ResetLastError();
      if(!OrderModify(ticket,fill,actualStop,tp,0,clrNONE))
      {EventLog(key,"RECONCILIATION_REQUIRED","TP_MODIFY_"+IntegerToString(GetLastError()));return false;}
   }
   if(!OrderSelect(ticket,SELECT_BY_TICKET) || OrderCloseTime()!=0 ||
      MathAbs(OrderStopLoss()-actualStop)>Point*0.1 ||
      MathAbs(OrderTakeProfit()-tp)>Point*0.1)
   {EventLog(key,"RECONCILIATION_REQUIRED","PROTECTION_VERIFY");return false;}
   EventLog(key,"OPENED","ticket="+IntegerToString(ticket)+
            " fill="+DoubleToString(fill,Digits)+" tp="+DoubleToString(tp,Digits));
   if(!FileDelete(RecoveryFile()))
   {EventLog(key,"RECONCILIATION_REQUIRED","MARKER_DELETE_FAILED");return false;}
   return true;
}
// Read-only snapshot of the loaded broker history, scoped to this EA.
// Balance-curve drawdown is not intratrade equity drawdown.
void ExportClosedHistory()
{
   int tickets[];
   datetime times[];
   double pnl[];
   int count=0;
   for(int i=0;i<OrdersHistoryTotal();i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) return;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber ||
         (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      ArrayResize(tickets,count+1);ArrayResize(times,count+1);ArrayResize(pnl,count+1);
      tickets[count]=OrderTicket();times[count]=OrderCloseTime();
      pnl[count]=OrderProfit()+OrderCommission()+OrderSwap();count++;
   }
   // Stable order by close time, then ticket.
   for(int j=1;j<count;j++)
   {
      int k=j;
      while(k>0 && (times[k]<times[k-1] ||
            (times[k]==times[k-1] && tickets[k]<tickets[k-1])))
      {
         int t=tickets[k];tickets[k]=tickets[k-1];tickets[k-1]=t;
         datetime dt=times[k];times[k]=times[k-1];times[k-1]=dt;
         double v=pnl[k];pnl[k]=pnl[k-1];pnl[k-1]=v;k--;
      }
   }
   int f=FileOpen(JournalName()+".closed_snapshot.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(f==INVALID_HANDLE){Print("HISTORY_EXPORT_FAILED");return;}
   FileWrite(f,"ticket","type","lots","open_time","close_time","entry","exit","sl","tp","profit","commission","swap","net");
   double net=0,gain=0,loss=0,peak=0,dd=0,sumR=0;int wins=0,rCount=0;
   for(int q=0;q<count;q++)
   {
      if(!OrderSelect(tickets[q],SELECT_BY_TICKET) || OrderCloseTime()!=times[q])
      {FileClose(f);Print("HISTORY_CHANGED");return;}
      FileWrite(f,OrderTicket(),OrderType(),OrderLots(),TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),
         TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),OrderOpenPrice(),OrderClosePrice(),
         OrderStopLoss(),OrderTakeProfit(),OrderProfit(),OrderCommission(),OrderSwap(),pnl[q]);
      double initialRisk=0;
      if(ReadFillRisk(tickets[q],initialRisk)){sumR+=pnl[q]/initialRisk;rCount++;}
      net+=pnl[q];gain+=MathMax(0.0,pnl[q]);loss+=MathMax(0.0,-pnl[q]);
      if(pnl[q]>0) wins++;
      peak=MathMax(peak,net);dd=MathMax(dd,peak-net);
   }
   FileFlush(f);FileClose(f);
   int m=FileOpen(JournalName()+".metrics.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(m==INVALID_HANDLE) return;
   FileWrite(m,"scope","trades","net","gross_gain","gross_loss","profit_factor","win_rate_pct","mean_net_per_trade","closed_pnl_drawdown","r_sample_count","expectancy_r");
   FileWrite(m,"LOADED_HISTORY_ONLY",count,net,gain,loss,
      loss>0?DoubleToString(gain/loss,8):"NA",
      count>0?DoubleToString(100.0*wins/count,8):"NA",
      count>0?DoubleToString(net/count,8):"NA",dd,rCount,
      rCount>0?DoubleToString(sumR/rCount,8):"NA");
   FileFlush(m);FileClose(m);
}
int OnInit()
{
   if(Symbol()!="XAUUSD" || Period()!=PERIOD_M5) return INIT_FAILED;
   if(TradeRiskPercent<=0 || TradeRiskPercent>5 || DailyRiskPercent<=0 || DailyRiskPercent>10 || AggregateRiskPercent<=0 || AggregateRiskPercent>10 || MaximumStopDistance<=0 || MaximumStopDistance>50 || !ParseClock(FridayCloseTime,fridayCloseMinutes) || !ParseClock(MondayOpenTime,mondayOpenMinutes)) return INIT_PARAMETERS_INCORRECT;
   // Hold an exclusive file handle for the full EA lifetime.
   // Terminal/tester sandboxes are separate. Common folder coordinates terminals.
   instanceLock=FileOpen(JournalName()+".instance.lock",
                         FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(instanceLock==INVALID_HANDLE)
   {Print("INSTANCE_LOCK_FAILED ",GetLastError());return INIT_FAILED;}
   lastBar=iTime(Symbol(),PERIOD_M5,0);
   Print("RoboAU 1 release locked; Friday close=",FridayCloseTime," Monday open=",MondayOpenTime," recovery marker=",RecoveryBlocked());
   ReconcileBrokerState();
   if(RecoveryBlocked()) Print("RECONCILIATION_REQUIRED: inspect broker orders and journal before release.");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   if(instanceLock!=INVALID_HANDLE){FileClose(instanceLock);instanceLock=INVALID_HANDLE;}
}
// Friday cutoff is in broker server time. No per-trade age limit.
// Actual holiday exceptions require a separately verified session schedule.
bool WeekendEntryBlocked(const datetime now)
{
   int day=TimeDayOfWeek(now);
   if(day==6 || day==0) return true;
   int minute=TimeHour(now)*60+TimeMinute(now);
   if(day==5) return minute>=fridayCloseMinutes;
   if(day==1) return minute<mondayOpenMinutes;
   return false;
}
void ManageWeekendClose()
{
   // Do not let a recovery marker prevent reducing known EA exposure.
   // The release lock and account gate still apply to every broker mutation.
   if(!EnableTrading || !AccountModeAllowed() ||
      (!IsTesting() && (!ExecutionReleaseAccepted || !IsTradeAllowed()))) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      int ticket=OrderTicket();
      double lots=OrderLots();
      RefreshRates();
      ResetLastError();
      if(!OrderClose(ticket,lots,type==OP_BUY?Bid:Ask,MaxSlippagePoints,clrNONE))
         EventLog(IntegerToString(ticket),"WEEKEND_CLOSE_FAILED",IntegerToString(GetLastError()));
      else EventLog(IntegerToString(ticket),"WEEKEND_CLOSED","MARKET");
   }
}
void OnTick()
{
   if(instanceLock==INVALID_HANDLE) return;
   if(WeekendEntryBlocked(TimeCurrent()))
   {
      ManageWeekendClose();
      // Do not evaluate a stale M5 signal after the weekend block.
      lastBar=iTime(Symbol(),PERIOD_M5,0);
      return;
   }
   datetime now=iTime(Symbol(),PERIOD_M5,0);
   if(now<=0 || now<=lastBar) return;
   Bar d[],h[],m[];
   if(!LoadBars(PERIOD_D1,60,d) || !LoadBars(PERIOD_H1,200,h) ||
      !LoadBars(PERIOD_M5,300,m)) return;
   // Avoid a mixed snapshot if a new M5 bar appeared while reading.
   if(iTime(Symbol(),PERIOD_M5,0)!=now) return;
   lastBar=now;
   ExportClosedHistory();
   int dir=Direction(d);
   Setup s;
   if(dir==0 || !Structure(h,dir,s) || !Confirm(m,s)) return;
   string key=Symbol()+"|"+IntegerToString(dir)+"|"+IntegerToString((long)s.breakout)
      +"|"+IntegerToString((long)s.retest)+"|"+IntegerToString((long)s.continuation);
   if(key==lastSetup) return;
   if(!ReserveSignal(key,s)) return;
   lastSetup=key;
   Print("CANDIDATE_ONLY ",key," confirmation=",TimeToString(s.confirmation),
         " SL=",DoubleToString(s.stop,Digits),
         " mode_allowed=",AccountModeAllowed());
   TradePlan p;
   string reason="";
   if(BrokerPlan(s,p,reason))
      Print("PLAN_ONLY ",key," lots=",DoubleToString(p.lots,8),
            " entry=",p.entry," SL=",p.stop," TP=",p.target," risk=",p.riskMoney);
   else Print("PLAN_REJECTED ",key," reason=",reason);
   if(ExecutionAllowed()) DispatchCandidate(key,s);
   else EventLog(key,"SIGNAL_ONLY","EXECUTION_GATE");
}
