import json, subprocess, glob, os
S=os.environ["SEPOLIA_RPC"]; L=os.environ["LASNA_RPC"]
def cast(*a): return subprocess.run(["cast",*a],capture_output=True,text=True,timeout=60).stdout.strip()
# event map from ABIs
ev={}
for f in ["ProceedsReactive","ProceedsVault","MockMarketplace","MockUSD","IReactive","ISystemContract","AbstractCallback","AbstractPayer"]:
    for p in glob.glob(f"out/{f}.sol/*.json"):
        for e in json.load(open(p)).get("abi",[]):
            if e["type"]!="event": continue
            sig=e["name"]+"("+",".join(i["type"] for i in e["inputs"])+")"
            t=cast("keccak",sig)
            ev[t]=(e,f)
names={"0xc1eea4ddd643462402539726a99f1a7ebd50dfe7":"ProceedsVault","0x406e7e7fa57f9534c9ce350afa4f23ef0f5faa6c":"MockMarketplace",
"0xd16be1d20f1ffee777f54bc2f65bd11a710e86c7":"MockUSD","0x445c336410f0a49e45893e10c25e39b804f81ba8":"ProceedsReactive",
"0xaa14d9cd0f788ca23d11805986c1d8bd035d23b4":"CallbackProxy","0x8888888888888888888888888888888888888888":"SystemContract",
"0xc1e54b2522627099ba45936cba066e6ada928993":"Owner/MainWallet"}
def decode(lg):
    t=lg["topics"]; e=ev.get(t[0])
    out={"address":lg["address"],"contract":names.get(lg["address"].lower(),lg["address"])}
    if not e: out["event"]="topic "+t[0][:10]; return out
    e=e[0]; out["event"]=e["name"]; args={}; ti=1; nonidx=[i for i in e["inputs"] if not i["indexed"]]
    for i in e["inputs"]:
        if i["indexed"]:
            v=t[ti]; ti+=1
            if i["type"]=="address": v="0x"+v[-40:]
            elif i["type"].startswith("uint"): v=str(int(v,16))
            args[i["name"]]=v
    if nonidx and lg["data"]!="0x":
        sig="x("+",".join(i["type"] for i in nonidx)+")"
        vals=cast("abi-decode","--input",sig,lg["data"]).split("\n")
        for i,v in zip(nonidx,vals): args[i["name"]]=v.split(" [")[0]
    out["args"]=args; return out
res={}
for line in open("runs/loops.tsv").read().splitlines()[1:]:
    lab,o,r,c=line.split("\t")
    if not lab.startswith(("loop2","loop3","loop4")): continue
    d={}
    for kind,rpc,hs in [("origin",S,o),("reactive",L,r),("callback",S,c)]:
        d[kind]=[]
        for h in hs.split(","):
            rc=json.loads(cast("receipt",h,"--json","--rpc-url",rpc)); rc=rc.get("data",rc)
            blk=int(rc["blockNumber"],16)
            ts=cast("block",str(blk),"-f","timestamp","--rpc-url",rpc)
            d[kind].append({"hash":h,"block":blk,"timestamp":int(ts),"status":int(rc["status"],16),"from":rc["from"],"to":rc["to"],
              "gasUsed":int(rc["gasUsed"],16),"logs":[decode(l) for l in rc["logs"]]})
    res[lab]=d
json.dump(res,open("demo/build/loops_decoded.json","w"),indent=1)
print(json.dumps(res,indent=1)[:6000])
