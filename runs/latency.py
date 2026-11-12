#!/usr/bin/env python3
"""Per-leg latency for every loop in runs/loops.tsv, from block timestamps read over RPC.

leg 1 = origin block -> Lasna reactive block, leg 2 = reactive block -> callback block, total = origin -> callback.
Uses the first reactive tx and the first callback tx of each loop. Writes runs/latency.tsv and prints a
markdown table. RPCs come from env: SEPOLIA_RPC, BASE_SEPOLIA_RPC, LASNA_RPC.
"""
import json, os, statistics, urllib.request

RPC = {
    "11155111": os.environ.get("SEPOLIA_RPC", "https://ethereum-sepolia-rpc.publicnode.com"),
    "84532": os.environ.get("BASE_SEPOLIA_RPC", "https://sepolia.base.org"),
    "lasna": os.environ.get("LASNA_RPC", "https://lasna-rpc.rnk.dev/"),
}
NAME = {"11155111": "Sepolia", "84532": "Base Sepolia"}


def rpc(url, method, params):
    req = urllib.request.Request(url, json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                                                  "params": params}).encode(),
                                 {"Content-Type": "application/json", "User-Agent": "latency"})
    return json.load(urllib.request.urlopen(req, timeout=30))["result"]


def ts(url, txh):
    r = rpc(url, "eth_getTransactionReceipt", [txh])
    b = rpc(url, "eth_getBlockByNumber", [r["blockNumber"], False])
    return int(b["timestamp"], 16), int(r["blockNumber"], 16), r["status"]


rows = []
lines = open(os.path.join(os.path.dirname(__file__), "loops.tsv")).read().strip().split("\n")[1:]
for line in lines:
    label, otx, rtx, ctx, chain = line.split("\t")
    o, ob, _ = ts(RPC[chain], otx)
    r, rb, _ = ts(RPC["lasna"], rtx.split(",")[0])
    c, cb, cst = min(ts(RPC[chain], h) for h in ctx.split(","))
    rows.append(dict(label=label, chain=NAME[chain], origin_block=ob, reactive_block=rb, callback_block=cb,
                     leg1=r - o, leg2=c - r, total=c - o))

out = os.path.join(os.path.dirname(__file__), "latency.tsv")
with open(out, "w") as f:
    keys = list(rows[0].keys())
    f.write("\t".join(keys) + "\n")
    for x in rows:
        f.write("\t".join(str(x[k]) for k in keys) + "\n")

print("| Loop | Chain | Origin → reactive (s) | Reactive → callback (s) | Full loop (s) | Origin blocks until callback |")
print("| --- | --- | ---: | ---: | ---: | ---: |")
for x in rows:
    print(f"| {x['label']} | {x['chain']} | {x['leg1']} | {x['leg2']} | **{x['total']}** | +{x['callback_block'] - x['origin_block']} |")
for ch in sorted({x["chain"] for x in rows}):
    t = [x["total"] for x in rows if x["chain"] == ch]
    print(f"\n{ch}: n={len(t)} median full loop {statistics.median(t)} s, min {min(t)} s, max {max(t)} s")
