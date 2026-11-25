#property strict
#property script_show_inputs
// Offline historical replay of the actual EA signal functions.
// No OnTick, OrderSend or broker execution is invoked.
#define OnInit RoboEAOnInit
#define OnDeinit RoboEAOnDeinit
#define OnTick RoboEAOnTick
#include "RoboAU_1.mq4"
#undef OnInit
#undef OnDeinit
#undef OnTick

bool ReadReplayBars(string name,Bar &b[])
{
   int f=FileOpen(name,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,';');
   if(f==INVALID_HANDLE){Print("REPLAY_INPUT_FAILED ",name);return false;}
   int n=0;ArrayResize(b,0);
   while(!FileIsEnding(f))
   {
      string t=FileReadString(f);
      if(t==""){break;}
      Bar x;
      x.time=StringToTime(t);x.o=FileReadNumber(f);x.h=FileReadNumber(f);
      x.l=FileReadNumber(f);x.c=FileReadNumber(f);
      if(x.time<=0 || x.l<=0 || x.h<x.l || x.o<x.l || x.o>x.h ||
         x.c<x.l || x.c>x.h || (n>0 && x.time<=b[n-1].time))
      {FileClose(f);return false;}
      ArrayResize(b,n+1,4096);b[n++]=x;
   }
   FileClose(f);return n>0;
}
void Window(const Bar &src[],int end,int n,Bar &dst[])
{
   ArrayResize(dst,n);
   for(int i=0;i<n;i++) dst[i]=src[end-n+1+i];
}
void OnStart()
{
   Bar d[],h[],m[],dw[],hw[],mw[];
   if(!ReadReplayBars("RoboAU_replay_D1.csv",d) ||
      !ReadReplayBars("RoboAU_replay_H1.csv",h) ||
      !ReadReplayBars("RoboAU_replay_M5.csv",m)) return;
   int f=FileOpen("RoboAU_replay_signals.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,';');
   if(f==INVALID_HANDLE)return;
   FileWrite(f,"cutoff","direction","breakout","retest","continuation","confirmation","entry","raw_stop");
   int di=-1,hi=-1,eligible=0,signals=0;
   string previous="";
   for(int i=300;i<ArraySize(m);i++)
   {
      datetime cutoff=m[i].time;
      while(di+1<ArraySize(d) && d[di+1].time+86400<=cutoff)di++;
      while(hi+1<ArraySize(h) && h[hi+1].time+3600<=cutoff)hi++;
      if(di<59 || hi<199 || m[i-1].time+300>cutoff)continue;
      eligible++;
      Window(d,di,60,dw);Window(h,hi,200,hw);Window(m,i-1,300,mw);
      int dir=Direction(dw);Setup s;
      if(dir==0 || !Structure(hw,dir,s) || !Confirm(mw,s))continue;
      string key=IntegerToString(dir)+"|"+IntegerToString((long)s.breakout)+"|"+
         IntegerToString((long)s.retest)+"|"+IntegerToString((long)s.continuation);
      if(key==previous)continue;
      previous=key;signals++;
      FileWrite(f,TimeToString(cutoff,TIME_DATE|TIME_SECONDS),dir,
         TimeToString(s.breakout,TIME_DATE|TIME_SECONDS),
         TimeToString(s.retest,TIME_DATE|TIME_SECONDS),
         TimeToString(s.continuation,TIME_DATE|TIME_SECONDS),
         TimeToString(s.confirmation,TIME_DATE|TIME_SECONDS),
         DoubleToString(m[i].o,8),DoubleToString(s.stop,8));
   }
   FileFlush(f);FileClose(f);
   Print("REPLAY_COMPLETE eligible=",eligible," signals=",signals);
}
