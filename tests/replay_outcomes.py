"""Offline OHLC outcome model for actual MQL4 replay signals; no broker calls."""
import csv, json, argparse, math
from pathlib import Path
from collections import defaultdict, Counter
from datetime import datetime
def read(p, header=True):
    with p.open(newline="",encoding="ascii") as f:
        return list(csv.DictReader(f,delimiter=";")) if header else list(csv.reader(f,delimiter=";"))
def run(root, initial, fee, slip, commission=0.0, spread=0.0):
    bars=read(root/"RoboAU_replay_M5.csv",False)
    signals=read(root/"RoboAU_replay_signals.csv")
    index={b[0]:i for i,b in enumerate(bars)}
    if len(index)!=len(bars): raise ValueError("duplicate bars")
    bybar=defaultdict(list)
    for s in signals: bybar[index[s["cutoff"]]].append(s)
    balance=initial; active=[]; closed=[]; rejected=0; peak=initial; dd=0; eqpeak=initial; eqdd=0
    day=None; daybase=initial; loss=0; curve=[]; reasons=Counter(); rejected_details=[]
    def finish(p,price,t,reason):
        nonlocal balance,loss,peak,dd
        exit=price*(1-p["dir"]*slip)
        net=p["qty"]*(p["dir"]*(exit-p["entry"])-fee*(p["entry"]+exit)-commission-spread)
        balance+=net;loss+=max(0,-net);peak=max(peak,balance);dd=max(dd,peak-balance)
        closed.append(dict(p,exit=exit,close_time=t,reason=reason,net=net,r=net/p["risk"],balance=balance))
        curve.append([t,balance])
    for i,b in enumerate(bars):
        t=b[0];o,h,l,c=map(float,b[1:5])
        if t[:10]!=day: day=t[:10];daybase=balance;loss=0
        for p in active[:]:
            if (o<=p["stop"] if p["dir"]==1 else o>=p["stop"]):
                finish(p,o,t,"STOP_GAP");active.remove(p)
            elif (o>=p["target"] if p["dir"]==1 else o<=p["target"]):
                finish(p,p["target"],t,"TP_GAP_CONSERVATIVE");active.remove(p)
        for s in bybar[i]:
            d=int(s["direction"]);entry=o*(1+d*slip)
            raw=float(s["raw_stop"]);stop=(math.floor(raw*100) if d==1 else math.ceil(raw*100))/100
            r=d*(entry-stop);target=entry+d*3*r
            equity=balance+sum(p["qty"]*p["dir"]*(o-p["entry"]) for p in active)
            risk=sum(p["qty"]*max(0,p["dir"]*(o-p["stop"])) for p in active)
            budget=min(.02*equity,.05*daybase-loss-risk,.10*equity-risk)
            unitloss=r+fee*(entry+stop)+slip*stop+commission+spread
            limits={"TRADE_2PCT":.02*equity,"DAILY_5PCT":.05*daybase-loss-risk,"AGGREGATE_10PCT":.10*equity-risk}
            binding=min(limits,key=limits.get)
            def reject(reason):
                reasons[reason]+=1
                rejected_details.append(dict(time=t,reason=reason,binding=binding,budget=budget,minimum_unit_loss=unitloss,stop_distance=r,equity=equity))
            if r<=0 or target<=0: rejected+=1;reject("INVALID_GEOMETRY");continue
            if budget<=0: rejected+=1;reject("NO_BUDGET_"+binding);continue
            # GerchikCo archived specification: one ounce per lot, integer lot step.
            qty=min(1000,math.floor(budget/unitloss+1e-10))
            if qty<1: rejected+=1;reject('MIN_LOT_'+binding);continue
            active.append(dict(time=t,dir=d,entry=entry,stop=stop,target=target,qty=qty,risk=qty*unitloss))
        for p in active[:]:
            hitstop=l<=p["stop"] if p["dir"]==1 else h>=p["stop"]
            hittp=h>=p["target"] if p["dir"]==1 else l<=p["target"]
            if hitstop or hittp:
                finish(p,p["stop"] if hitstop else p["target"],t,"SL" if hitstop else "TP");active.remove(p)
        equity=balance+sum(p["qty"]*p["dir"]*(c-p["entry"]) for p in active)
        eqpeak=max(eqpeak,equity);eqdd=max(eqdd,eqpeak-equity)
    gains=sum(max(0,p["net"]) for p in closed);losses=sum(max(0,-p["net"]) for p in closed)
    n=len(closed)
    return dict(signals=len(signals),closed=n,open_censored=len(active),rejected=rejected,initial=initial,final_balance=balance,net=balance-initial,profit_factor=gains/losses if losses else None,win_rate=sum(p["net"]>0 for p in closed)/n if n else None,expectancy_r=sum(p["r"] for p in closed)/n if n else None,closed_drawdown=dd,bar_close_equity_drawdown=eqdd,fee_per_side=fee,slippage_per_side=slip,commission_round_turn=commission,spread_round_turn=spread,curve=curve,trades=closed,rejection_reasons=dict(reasons),rejected_details=rejected_details)
if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("root",type=Path);p.add_argument("output",type=Path);p.add_argument("--initial",type=float,default=1189.05)
    a=p.parse_args()
    result={str(d):run(a.root,d,0,0,commission=.10,spread=.14) for d in (1189.05,2000,3000,5000,10000)}
    a.output.write_text(json.dumps(result,indent=2),encoding="utf-8")
    print(json.dumps({k:{x:y for x,y in v.items() if x not in ("curve","trades","rejected_details")} for k,v in result.items()},indent=2))
