"""Independent signal outcomes with actual market exit at first available bar after timeout."""
import csv,json,sys,math
from pathlib import Path
from datetime import datetime,timedelta
from collections import Counter
root=Path(sys.argv[1]); out=Path(sys.argv[2])
with (root/"RoboAU_replay_M5.csv").open() as f:
    bars=[(datetime.strptime(r[0],"%Y.%m.%d %H:%M:%S"),*map(float,r[1:5])) for r in csv.reader(f,delimiter=";")]
with (root/"RoboAU_replay_signals.csv").open() as f: signals=list(csv.DictReader(f,delimiter=";"))
idx={b[0]:i for i,b in enumerate(bars)}
boundary=datetime(2025,12,30,13,50)
# Proxy: final observed Friday M5 bar before a weekend gap; open is five minutes before inferred session end.
weekend={bars[i][0] for i in range(len(bars)-1) if bars[i][0].weekday()==4 and (bars[i+1][0]-bars[i][0]).total_seconds()>=24*3600}
print("WEEKEND_PROXY",len(weekend),sorted(Counter(t.strftime("%H:%M") for t in weekend).items()))
def simulate(s,hours,delay=0,original_cost=False,week=False,cap=None):
    t=datetime.strptime(s["cutoff"],"%Y.%m.%d %H:%M:%S")+timedelta(minutes=delay)
    d=int(s["direction"]); i=idx.get(t)
    if i is None:return dict(reason="MISSING_ENTRY")
    slip=.0002 if original_cost else 0
    entry=bars[i][1]*(1+d*slip)
    raw=float(s["raw_stop"])
    stop=raw if original_cost else (math.floor(raw*100) if d==1 else math.ceil(raw*100))/100
    r=d*(entry-stop)
    if r<=0:return dict(reason="INVALID")
    if cap is not None and r>cap:return dict(reason="SL_FILTER",direction=d,stop_distance=r,entry_time=t.isoformat())
    if week and t in weekend:return dict(reason="WEEKEND_FILTER",direction=d,stop_distance=r,entry_time=t.isoformat())
    target=entry+d*3*r
    deadline=t+timedelta(hours=hours) if hours else datetime.max
    for j in range(i,len(bars)):
        bt,o,h,l,c=bars[j]
        if j>i and d*(o-stop)<=0: exit=o;reason="STOP_GAP"
        elif j>i and d*(o-target)>=0: exit=target;reason="TP"
        elif week and bt in weekend: exit=o;reason="WEEKEND"
        elif bt>=deadline: exit=o;reason="TIME"
        elif (l<=stop if d==1 else h>=stop): exit=stop;reason="SL"
        elif (h>=target if d==1 else l<=target): exit=target;reason="TP"
        else:continue
        exit*=1-d*slip
        net=d*(exit-entry)-(.0005*(entry+exit) if original_cost else .24)
        return dict(reason=reason,r=net/r,stop_distance=r,direction=d,entry_time=t.isoformat(),exit_time=bt.isoformat())
    return dict(reason="CENSORED",direction=d,stop_distance=r,entry_time=t.isoformat())
def summarize(rows):
    v=[x["r"] for x in rows if "r" in x];g=sum(max(0,x) for x in v);l=sum(max(0,-x) for x in v)
    return dict(n=len(rows),resolved=len(v),counts=dict(Counter(x["reason"] for x in rows)),sum_r=sum(v),pf=g/l if l else None,mean_r=sum(v)/len(v) if v else None,wins=sum(x>0 for x in v),time_r=sum(x["r"] for x in rows if x["reason"]=="TIME"))
results={};details={}
for hours in (110,120,None):
 for week in (False,True):
  for cap in (None,50):
   rows=[simulate(s,hours,week=week,cap=cap) for s in signals]
   key=f"{hours}/{week}/{cap}";details[key]=rows
   results[key]={k:summarize(v) for k,v in {"all":rows,"BUY":[r for r in rows if r.get("direction")==1],"SELL":[r for r in rows if r.get("direction")==-1],"discovery":[r for r in rows if r.get("entry_time","9999")<boundary.isoformat()],"later":[r for r in rows if r.get("entry_time","")>=boundary.isoformat()]}.items()}
   print(key,json.dumps(results[key],separators=(",",":")))
out.write_text(json.dumps(dict(summary=results,details=details,weekend_proxy=[t.isoformat() for t in sorted(weekend)]),indent=2))
