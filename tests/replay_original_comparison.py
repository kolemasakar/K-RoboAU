"""Compare actual MQL4 signals using the original KAI outcome function."""
import csv,json,sys
from pathlib import Path
from datetime import datetime,timedelta
from collections import Counter
root=Path(sys.argv[1]); kai=Path(sys.argv[2]); out=Path(sys.argv[3])
sys.path.insert(0,str(kai))
from tools.run_mt4_strategy_a_frozen_outcomes import simulate_outcome_wall_clock
def iso(s): return s.replace(".","-").replace(" ","T")
with (root/"RoboAU_replay_M5.csv").open() as f:
    bars=[dict(time=iso(r[0]),open=float(r[1]),high=float(r[2]),low=float(r[3]),close=float(r[4])) for r in csv.reader(f,delimiter=";")]
with (root/"RoboAU_replay_signals.csv").open() as f: signals=list(csv.DictReader(f,delimiter=";"))
idx={b["time"]:i for i,b in enumerate(bars)}
boundary="2025-12-30T13:50:00"
end=(datetime.fromisoformat(bars[-1]["time"])+timedelta(minutes=5)).isoformat()
original=json.loads((kai/"reports/audits/a1_metals_discovery_outcomes.json").read_text(encoding="utf-8-sig"))
old={r["continuation_time"]:r for r in original["rows"] if r["broker_symbol"]=="XAUUSD"}
def summary(rows):
    c=Counter(r["outcome"] for r in rows); v=[r["net_r"] for r in rows if "net_r" in r]
    gains=sum(max(0,x) for x in v); losses=sum(max(0,-x) for x in v)
    return dict(count=len(rows),counts=dict(c),sum_r=sum(v),mean_r=sum(v)/len(v) if v else None,pf=gains/losses if losses else None)
results={}; details={}
for period in ("discovery","later","all"):
 for delay in (0,5):
  for limit in (168,100000):
   for direction in ("ALL","BUY","SELL"):
    rows=[]
    for s in signals:
     t=iso(s["cutoff"]); d="BUY" if int(s["direction"])==1 else "SELL"
     if period=="discovery" and t>=boundary or period=="later" and t<boundary or direction!="ALL" and d!=direction:continue
     entry=(datetime.fromisoformat(t)+timedelta(minutes=delay)).isoformat()
     stop=float(s["raw_stop"])
     a=simulate_outcome_wall_clock(bars,idx,dict(entry_time=entry,direction=d,stop_price=stop),dict(max_observation_hours=limit,slippage_bps_per_side=2,fee_bps_per_side=5,risk_reward=3),partition_end_exclusive=boundary if period=="discovery" else end)
     rows.append(dict(a,continuation=iso(s["continuation"]),direction=d))
    key=f"{period}/{delay}/{limit}/{direction}";results[key]=summary(rows);details[key]=rows
matched=details["discovery/5/168/ALL"]
print("PARITY",len(matched),sum(r["outcome"]==old[r["continuation"]]["outcome"]["outcome"] for r in matched),max(abs(r["net_r"]-old[r["continuation"]]["outcome"]["net_r"]) for r in matched if "net_r" in r and "net_r" in old[r["continuation"]]["outcome"]))
for k,v in results.items(): print(k,json.dumps(v))
out.write_text(json.dumps(dict(summary=results,details=details),indent=2))
