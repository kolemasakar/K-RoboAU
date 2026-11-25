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
def simulate(s,hours,delay=0,original_cost=False):
    t=datetime.strptime(s["cutoff"],"%Y.%m.%d %H:%M:%S")+timedelta(minutes=delay)
    d=int(s["direction"]); i=idx.get(t)
    if i is None:return dict(reason="MISSING_ENTRY")
    slip=.0002 if original_cost else 0
    entry=bars[i][1]*(1+d*slip)
    raw=float(s["raw_stop"])
    stop=raw if original_cost else (math.floor(raw*100) if d==1 else math.ceil(raw*100))/100
    r=d*(entry-stop)
    if r<=0:return dict(reason="INVALID")
    target=entry+d*3*r
    deadline=t+timedelta(hours=hours) if hours else datetime.max
    for j in range(i,len(bars)):
        bt,o,h,l,c=bars[j]
        if j>i and d*(o-stop)<=0: exit=o;reason="STOP_GAP"
        elif j>i and d*(o-target)>=0: exit=target;reason="TP"
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
results={}; details={}
for cost in (False,True):
 for delay in (0,5):
  for hours in (24,48,72,96,120,168,336,None):
   rows=[simulate(s,hours,delay,cost) for s in signals]
   key=f"{cost}/{delay}/{hours}";details[key]=rows
   groups={"all":rows,"BUY":[r for r in rows if r.get("direction")==1],"SELL":[r for r in rows if r.get("direction")==-1],"discovery":[r for r in rows if r.get("entry_time","9999")<boundary.isoformat()],"later":[r for r in rows if r.get("entry_time","")>=boundary.isoformat()]}
   for lo,hi in ((0,25),(25,50),(50,100),(100,100000)):
    groups[f"SL_{lo}_{hi}"]=[r for r in rows if lo<=r.get("stop_distance",-1)<hi]
   results[key]={k:summarize(v) for k,v in groups.items()}
   if not cost and delay==0: print(key,json.dumps(results[key],separators=(",",":")))
   elif cost and delay==5: print("ORIGINAL_COST",key,json.dumps(results[key]["all"],separators=(",",":")))
out.write_text(json.dumps(dict(summary=results,details=details),indent=2))
