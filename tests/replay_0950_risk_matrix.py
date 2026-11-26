"""Offline OHLC outcome model for actual MQL4 replay signals; no broker calls."""
import csv, json, argparse, math
from pathlib import Path
from collections import defaultdict, Counter
from datetime import datetime, timedelta
from functools import lru_cache
@lru_cache(maxsize=1)
def load(root, friday="21:15", monday="03:00"):
    f=datetime.strptime(friday,"%H:%M").time()
    m=datetime.strptime(monday,"%H:%M").time()
    bars=read(root/"RoboAU_replay_M5.csv",False)
    signals=read(root/"RoboAU_replay_signals.csv")
    times=[datetime.strptime(b[0],"%Y.%m.%d %H:%M:%S") for b in bars]
    # Archive is already broker wall clock. Do not shift bars twice.
    blocked={b[0] for b,t in zip(bars,times) if t.weekday()>=5 or (t.weekday()==4 and t.time()>=f) or (t.weekday()==0 and t.time()<m)}
    fridays={t.date() for t in times if t.weekday()==4}
    missing=sorted(str(d) for d in fridays if not any(t.date()==d and t.weekday()==4 and t.time()>=f for t in (datetime.strptime(x,"%Y.%m.%d %H:%M:%S") for x in blocked)))
    return bars,signals,blocked,missing,times
def read(p, header=True):
    with p.open(newline="",encoding="ascii") as f:
        return list(csv.DictReader(f,delimiter=";")) if header else list(csv.reader(f,delimiter=";"))
def run(root, initial, fee, slip, commission=0.0, spread=0.0, trade_rate=.02, daily_rate=.05, friday="21:15", monday="03:00", swap_buy=-.5347, swap_sell=.2796, gap_at_open=False):
    bars,signals,weekend,missing,times=load(root,friday,monday)
    index={b[0]:i for i,b in enumerate(bars)}
    if len(index)!=len(bars): raise ValueError("duplicate bars")
    bybar=defaultdict(list)
    for s in signals: bybar[index[s["cutoff"]]].append(s)
    balance=initial; active=[]; closed=[]; rejected=0; peak=initial; dd=0; eqpeak=initial; eqdd=0
    ddpct=0; eqddpct=0
    day=None; daybase=initial; loss=0; previous=None; curve=[]; reasons=Counter(); rejected_details=[]
    def finish(p,price,t,reason):
        nonlocal balance,loss,peak,dd,ddpct
        exit=price*(1-p["dir"]*slip)
        net=p["qty"]*(p["dir"]*(exit-p["entry"])-fee*(p["entry"]+exit)-commission)+p["swap"]
        balance+=net;loss+=max(0,-net);peak=max(peak,balance);dd=max(dd,peak-balance);ddpct=max(ddpct,(peak-balance)/peak)
        closed.append(dict(p,exit=exit,close_time=t,reason=reason,net=net,r=net/p["risk"],balance=balance))
        curve.append([t,balance])
    for i,b in enumerate(bars):
        t=b[0];o,h,l,c=map(float,b[1:5])
        dt=times[i]
        if t[:10]!=day:
            day=t[:10];daybase=balance;loss=0
            if previous is not None:
                rollover=previous.date()
                while rollover<dt.date():
                    if rollover.weekday()<5:
                        for p in active: p["swap"]+=p["qty"]*(swap_buy if p["dir"]==1 else swap_sell)*(3 if rollover.weekday()==2 else 1)
                    rollover+=timedelta(days=1)
        previous=dt
        for p in active[:]:
            mark=o+(spread if p["dir"]==-1 else 0)
            if (mark<=p["stop"] if p["dir"]==1 else mark>=p["stop"]):
                finish(p,mark if gap_at_open else p["stop"],t,"STOP_GAP");active.remove(p)
            elif (mark>=p["target"] if p["dir"]==1 else mark<=p["target"]):
                finish(p,p["target"],t,"TP_GAP_CONSERVATIVE");active.remove(p)
            elif t in weekend:
                finish(p,mark,t,"WEEKEND");active.remove(p)
        for s in bybar[i]:
            d=int(s["direction"]);entry=(o+(spread if d==1 else 0))*(1+d*slip)
            raw=float(s["raw_stop"]);stop=(math.floor(raw*100) if d==1 else math.ceil(raw*100))/100
            r=d*(entry-stop);target=entry+d*3*r
            equity=balance+sum(p["qty"]*p["dir"]*(o+(spread if p["dir"]==-1 else 0)-p["entry"])+p["swap"]-commission*p["qty"] for p in active)
            risk=sum(p["qty"]*max(0,p["dir"]*(o+(spread if p["dir"]==-1 else 0)-p["stop"])) for p in active)
            budget=min(trade_rate*equity, .10*equity-risk, daily_rate*daybase-loss-risk if daily_rate is not None and closed else math.inf)
            unitloss=r+fee*(entry+stop)+slip*stop+commission+spread
            limits={"TRADE":trade_rate*equity,"AGGREGATE_10PCT":.10*equity-risk}
            if daily_rate is not None and closed: limits["DAILY"]=daily_rate*daybase-loss-risk
            binding=min(limits,key=limits.get)
            def reject(reason):
                reasons[reason]+=1
                rejected_details.append(dict(time=t,reason=reason,binding=binding,budget=budget,minimum_unit_loss=unitloss,stop_distance=r,equity=equity))
            if r<=0 or target<=0 or d*(o+(spread if d==-1 else 0)-stop)<=0: rejected+=1;reject("INVALID_GEOMETRY");continue
            if r>50: rejected+=1;reject("SL_FILTER");continue
            if t in weekend: rejected+=1;reject("WEEKEND_FILTER");continue
            if budget<=0: rejected+=1;reject("NO_BUDGET_"+binding);continue
            # GerchikCo archived specification: one ounce per lot, integer lot step.
            qty=min(1000,math.floor(budget/unitloss+1e-10))
            if qty<1: rejected+=1;reject('MIN_LOT_'+binding);continue
            active.append(dict(time=t,dir=d,entry=entry,stop=stop,target=target,qty=qty,risk=qty*unitloss,swap=0.0,equity_at_entry=equity,open_risk_before=risk,day_base=daybase,day_loss=loss,daily_available=bool(closed),budget=budget))
        for p in active[:]:
            hitstop=l<=p["stop"] if p["dir"]==1 else h+spread>=p["stop"]
            hittp=h>=p["target"] if p["dir"]==1 else l+spread<=p["target"]
            if hitstop or hittp:
                finish(p,p["stop"] if hitstop else p["target"],t,"SL" if hitstop else "TP");active.remove(p)
        equity=balance+sum(p["qty"]*p["dir"]*(c+(spread if p["dir"]==-1 else 0)-p["entry"])+p["swap"]-commission*p["qty"] for p in active)
        eqpeak=max(eqpeak,equity);eqdd=max(eqdd,eqpeak-equity);eqddpct=max(eqddpct,(eqpeak-equity)/eqpeak)
    gains=sum(max(0,p["net"]) for p in closed);losses=sum(max(0,-p["net"]) for p in closed)
    n=len(closed)
    return dict(signals=len(signals),closed=n,open_censored=len(active),rejected=rejected,initial=initial,final_balance=balance,net=balance-initial,profit_factor=gains/losses if losses else None,win_rate=sum(p["net"]>0 for p in closed)/n if n else None,expectancy_r=sum(p["r"] for p in closed)/n if n else None,closed_drawdown=dd,closed_drawdown_pct=100*ddpct,equity_drawdown_pct=100*eqddpct,trade_rate=trade_rate,daily_rate=daily_rate,weekend_cutoff=friday,monday_open=monday,swap_buy_estimate=swap_buy,swap_sell_estimate=swap_sell,gap_at_open=gap_at_open,missing_fridays=missing,max_stop=50,bar_close_equity_drawdown=eqdd,fee_per_side=fee,slippage_per_side=slip,commission_round_turn=commission,spread_round_turn=spread,curve=curve,trades=closed,rejection_reasons=dict(reasons),rejected_details=rejected_details)
if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("root",type=Path);p.add_argument("output",type=Path);p.add_argument("--initial",type=float,default=1189.05)
    p.add_argument("--friday",default="21:15");p.add_argument("--monday",default="03:00");p.add_argument("--gap-at-open",action="store_true")
    a=p.parse_args()
    result={f"{d}/{t}/{l}":run(a.root,d,0,0,commission=.10,spread=.14,trade_rate=t,daily_rate=l,friday=a.friday,monday=a.monday,gap_at_open=a.gap_at_open) for d in (1189.05,2000,3000,5000,10000) for t in (.005,.01,.02,.05) for l in (.02,.05,.10,None)}
    print("MISSING_FRIDAYS",load(a.root,a.friday,a.monday)[3])
    a.output.write_text(json.dumps(result,indent=2),encoding="utf-8")
    for k,v in result.items():
        assert v["closed"]+v["open_censored"]+v["rejected"]==145
        print(k,round(v["net"],2),v["closed"],v["open_censored"],round(v["profit_factor"],3) if v["profit_factor"] is not None else "NA",round(v["equity_drawdown_pct"],2),round(100*v["net"]/v["initial"],2))
