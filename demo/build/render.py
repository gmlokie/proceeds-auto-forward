"""Render demo slides for Proceeds Auto-Forward. Output: frames/NN_name.png + segments.json (durations)."""
import json, os, datetime
from PIL import Image, ImageDraw, ImageFont
from pygments import lex
from pygments.lexers import SolidityLexer
from pygments.token import Token

W, H = 1920, 1080
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "frames")
os.makedirs(OUT, exist_ok=True)

F = "/usr/share/fonts/truetype/dejavu/"
def font(size, bold=False, mono=False):
    name = ("DejaVuSansMono" if mono else "DejaVuSans") + ("-Bold" if bold else "") + ".ttf"
    return ImageFont.truetype(F + name, size)

BG = (13, 17, 28); PANEL = (22, 28, 44); PANEL2 = (30, 38, 60); LINE = (52, 64, 96)
FG = (230, 236, 248); DIM = (140, 152, 180); ACC = (88, 196, 255); GRN = (92, 220, 140)
YEL = (255, 204, 92); RED = (255, 110, 110); PUR = (190, 150, 255)

segments = []  # (file, seconds)

def base(caption=None, step=None):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 6], fill=ACC)
    d.text((48, 26), "Proceeds Auto-Forward", font=font(26, True), fill=FG)
    d.text((420, 30), "Reactive Omni Buildathon · Set It and Forget It · testnet", font=font(22), fill=DIM)
    if step:
        tw = d.textlength(step, font=font(22, True))
        d.text((W - 48 - tw, 30), step, font=font(22, True), fill=ACC)
    if caption:
        d.rectangle([0, H - 138, W, H], fill=(8, 11, 19))
        d.rectangle([0, H - 138, 10, H], fill=ACC)
        wrap_text(d, caption, (56, H - 118), font(34), FG, W - 112, 46)
    return im, d

def wrap_text(d, text, xy, f, fill, maxw, lh):
    x, y = xy
    for para in text.split("\n"):
        words, line = para.split(" "), ""
        for w_ in words:
            t = (line + " " + w_).strip()
            if d.textlength(t, font=f) > maxw and line:
                d.text((x, y), line, font=f, fill=fill); y += lh; line = w_
            else:
                line = t
        d.text((x, y), line, font=f, fill=fill); y += lh
    return y

TIMING = json.load(open(os.path.join(HERE, "timing.json"))) if os.path.exists(os.path.join(HERE, "timing.json")) else {}

def save(im, name, secs):
    secs = TIMING.get(name, secs)  # narration-fitted durations (build_vo.py)
    p = os.path.join(OUT, f"{len(segments):02d}_{name}.png")
    im.save(p); segments.append((p, secs))

def rr(d, box, fill, outline=None, r=18, width=2):
    d.rounded_rectangle(box, r, fill=fill, outline=outline, width=width)

# ---------------------------------------------------------------- 1 title
im, d = base()
d.text((140, 300), "Proceeds Auto-Forward", font=font(96, True), fill=FG)
d.text((144, 430), "Sell something, get paid — the money sweeps to your main wallet by itself.", font=font(40), fill=ACC)
d.text((144, 500), "No bot. No keeper. No cron job.", font=font(40), fill=FG)
for i, (t, c) in enumerate([("Origin: Ethereum Sepolia", GRN), ("Reactive: Lasna (5318007)", PUR), ("Destination: Sepolia vault", YEL)]):
    x = 144 + i * 540
    rr(d, [x, 620, x + 500, 690], PANEL, c)
    d.text((x + 24, 637), t, font=font(30, True), fill=c)
d.text((144, 780), "Reactive Omni Buildathon · track: Set It and Forget It · all on testnets, every tx linked", font=font(28), fill=DIM)
save(im, "title", 7)

# ---------------------------------------------------------------- 2 problem
im, d = base("A hot sales wallet should never sit on proceeds. Point the payout address at a vault; Reactive Network moves the money under rules you set.", "The idea")
d.text((120, 150), "The problem", font=font(52, True), fill=FG)
pts = [("Sales / invoice wallets are hot wallets", "keys live on servers, bots and browsers"),
       ("Sweeping by hand is slow and forgotten", "or needs a keeper bot you have to babysit"),
       ("The fix: event-driven, on-chain", "payment event → reactive contract → callback → forward")]
y = 250
for i, (a, b) in enumerate(pts):
    c = [RED, YEL, GRN][i]
    rr(d, [120, y, 1800, y + 170], PANEL, c)
    d.text((160, y + 30), a, font=font(44, True), fill=c)
    d.text((160, y + 98), b, font=font(34), fill=DIM)
    y += 200
save(im, "problem", 9)

# ---------------------------------------------------------------- 3 architecture
im, d = base("A Transfer or Sale paying the vault is seen by Reactive Network; ProceedsReactive asks for a callback; the vault applies the owner's rules and forwards.", "Architecture")
def box(x, y, w, h, title, sub, c):
    rr(d, [x, y, x + w, y + h], PANEL, c, width=3)
    d.text((x + 22, y + 18), title, font=font(32, True), fill=c)
    yy = y + 66
    for s in sub:
        d.text((x + 22, yy), s, font=font(24), fill=FG); yy += 34
def arrow(x1, y1, x2, y2, c, label=None, lx=None, ly=None):
    d.line([x1, y1, x2, y2], fill=c, width=5)
    import math
    a = math.atan2(y2 - y1, x2 - x1)
    pts_ = [(x2, y2), (x2 - 22 * math.cos(a - 0.4), y2 - 22 * math.sin(a - 0.4)), (x2 - 22 * math.cos(a + 0.4), y2 - 22 * math.sin(a + 0.4))]
    d.polygon(pts_, fill=c)
    if label:
        d.text((lx, ly), label, font=font(24, True), fill=c)
# lanes
for (x, t, c) in [(60, "ORIGIN · Sepolia", GRN), (700, "REACTIVE · Lasna", PUR), (1300, "DESTINATION · Sepolia", YEL)]:
    d.text((x, 110), t, font=font(26, True), fill=c)
box(60, 160, 560, 190, "ERC20 Transfer", ["MockUSD.transfer(vault, amt)", "Transfer(from, to = vault, value)"], GRN)
box(60, 400, 560, 220, "Marketplace Sale", ["MockMarketplace.buy(listing)", "pays vault in ERC20 or ETH", "Sale(id, payee = vault, token, price…)"], GRN)
box(700, 250, 540, 300, "ProceedsReactive", ["subscribe: topic2 == vault", "react(LogRecord):", "  decode, check vault registered", "  emit ProceedsDetected", "  requestCallbackV_1_0(...)"], PUR)
box(1300, 160, 560, 330, "ProceedsVault", ["onProceeds(...) via callback proxy", "auth: proxy + our reactive", "dedupe (chain, txHash, token)", "pause · allowlist · min · keep", "native gas buffer", "never reverts on a rule"], YEL)
box(1300, 560, 560, 130, "Main wallet", ["receives proceeds − keep"], ACC)
arrow(620, 255, 700, 330, GRN)
arrow(620, 510, 700, 450, GRN)
arrow(1240, 400, 1300, 330, PUR, "callback", 1246, 506)
arrow(1580, 490, 1580, 560, YEL)
rr(d, [60, 730, 1860, 920], PANEL2, LINE)
d.text((90, 750), "Every step leaves a log:", font=font(28, True), fill=FG)
d.text((90, 800), "Lasna: ProceedsDetected · ForwardRequested      Sepolia vault: CallbackReceived · ProceedsForwarded · ProceedsSkipped(reason)", font=font(24), fill=DIM)
d.text((90, 845), "Skip reasons: 0 Paused · 1 TokenNotAllowed · 2 BelowMinimum · 3 AlreadyProcessed · 4 NothingToForward · 5 TransferFailed", font=font(24), fill=DIM)
save(im, "architecture", 15)

# ---------------------------------------------------------------- code slides
COL = {Token.Keyword: PUR, Token.Keyword.Type: ACC, Token.Name.Builtin: ACC, Token.Comment: (110, 125, 150),
       Token.Literal.Number: YEL, Token.Literal.String: GRN, Token.Name.Function: (120, 220, 255), Token.Operator: FG}
def tcolor(tt):
    while tt is not None:
        if tt in COL: return COL[tt]
        tt = tt.parent
    return FG
def code_slide(name, title, path, code, caption, secs, hl=()):
    im, d = base(caption, "Code")
    d.text((80, 100), title, font=font(40, True), fill=FG)
    d.text((80, 156), path, font=font(24, mono=True), fill=DIM)
    rr(d, [60, 205, 1860, 925], PANEL, LINE)
    lines = code.strip("\n").split("\n")
    fs = 27 if len(lines) <= 21 else 23
    lh = int(fs * 1.32)
    f = font(fs, mono=True)
    cw = d.textlength("M", font=f)
    y0 = 228
    for i in hl:
        d.rectangle([64, y0 + i * lh - 3, 1856, y0 + (i + 1) * lh - 3], fill=(40, 52, 84))
    x, y = 100, y0
    for tt, val in lex(code.strip("\n"), SolidityLexer()):
        for j, part in enumerate(val.split("\n")):
            if j > 0:
                y += lh; x = 100
            if part:
                d.text((x, y), part, font=f, fill=tcolor(tt)); x += cw * len(part)
    save(im, name, secs)

code_slide("code_subscribe", "1 · Subscribe to money arriving at the vault", "src/reactive/ProceedsReactive.sol  ·  watchToken / watchMarketplace → _route", """
function watchToken(uint256 chainId_, address token_, address vault_) external onlyOwner {
    _route(RouteKind.Token, chainId_, token_, vault_, true);
}
function watchMarketplace(uint256 chainId_, address marketplace_, address vault_) external onlyOwner {
    _route(RouteKind.Marketplace, chainId_, marketplace_, vault_, true);
}

// inside _route(): one subscription per route, filtered by topic2 == vault
uint256 topic0 = kind_ == RouteKind.Token ? TRANSFER_TOPIC0 : SALE_TOPIC0;
vaultRoutes[_vaultKey(chainId_, vault_)] += 1;
SYSTEM.subscribe(
    chainId_,                    // origin chain, e.g. Sepolia 11155111
    source_,                     // MockUSD or MockMarketplace
    topic0,                      // Transfer(...) or Sale(...)
    REACTIVE_IGNORE,
    uint256(uint160(vault_)),    // topic2: the recipient / payee must be our vault
    REACTIVE_IGNORE
);
""", "The owner registers routes on Lasna. Each route is a Reactive subscription: Transfer or Sale events whose recipient (topic2) is the vault.", 12, hl=(16,))

code_slide("code_react", "2 · react(): decode the event, request a callback", "src/reactive/ProceedsReactive.sol  ·  react(LogRecord)", """
function react(LogRecord calldata log_) external onlySystem {
    if (log_.topic0 == TRANSFER_TOPIC0 && log_.opCode == 3) {        // ERC20 only (ERC721 has 4 topics)
        vault = address(uint160(log_.topic2));
        token = log_.contractAddress;
        amount = abi.decode(log_.data, (uint256));
    } else if (log_.topic0 == SALE_TOPIC0 && log_.opCode == 4) {     // Sale(id, payee, token, price, ...)
        vault = address(uint160(log_.topic2));
        token = address(uint160(log_.topic3));
        (amount,,) = abi.decode(log_.data, (uint256, address, address));
    } else return;                                                  // not ours: cheap no-op, never revert
    if (amount == 0 || !isVault(log_.chainId, vault)) return;

    emit ProceedsDetected(log_.chainId, vault, token, amount, kind, log_.txHash);
    bytes memory payload = abi.encodeWithSignature(
        "onProceeds(address,uint256,address,uint256,uint256)",
        address(0), log_.chainId, token, amount, log_.txHash);       // arg 0 = reactive id, set by network
    SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({
        chainId: log_.chainId, recipient: vault, gasLimit: callbackGasLimit, payload: payload }));
}
""", "Reactive Network calls react() with the matching log. It decodes token and amount, checks the vault is registered, logs it and requests a callback to the vault.", 14, hl=(16, 17))

code_slide("code_vault", "3 · onProceeds(): the vault applies the owner's rules", "src/destination/ProceedsVault.sol  ·  AbstractCallback", """
function onProceeds(address reactive_, uint256 originChainId_, address token_,
                    uint256 amount_, uint256 originTxHash_)
    external onlyServiceProvider onlyCallbackSender(reactive_)      // callback proxy + our reactive only
{
    emit CallbackReceived(originChainId_, originTxHash_, token_, amount_);
    bytes32 key = keccak256(abi.encode(originChainId_, originTxHash_, token_));
    if (processed[key]) return _skip(token_, amount_, SkipReason.AlreadyProcessed, originTxHash_);
    processed[key] = true;
    if (paused) return _skip(token_, amount_, SkipReason.Paused, originTxHash_);
    TokenRule memory rule = rules[token_];
    if (!rule.allowed) return _skip(token_, amount_, SkipReason.TokenNotAllowed, originTxHash_);
    if (amount_ < rule.minAmount) return _skip(token_, amount_, SkipReason.BelowMinimum, originTxHash_);

    (uint256 send, uint256 kept) = quoteForward(token_, amount_);    // min(reported, spendable) - keep
    if (send == 0) return _skip(token_, amount_, SkipReason.NothingToForward, originTxHash_);
    if (!_transferOut(token_, mainWallet, send))
        return _skip(token_, amount_, SkipReason.TransferFailed, originTxHash_);
    emit ProceedsForwarded(token_, mainWallet, send, kept, originTxHash_);
}
""", "Only the callback proxy carrying our reactive contract's id can call it. Dedupe, pause, allowlist, minimum, keep and gas buffer; a rule miss is an event, not a revert.", 14, hl=(2, 13))

# ---------------------------------------------------------------- forge test typewriter
ft = open(os.path.join(ROOT, "runs", "forge_test.txt")).read().strip("\n").split("\n")
ft = [l for l in ft if l.strip() and not l.startswith("No files changed")]
def term(nlines, cmd_chars, secs, name, caption):
    im, d = base(caption, "Tests")
    rr(d, [60, 100, 1860, 925], (6, 8, 12), LINE)
    for i, c in enumerate([RED, YEL, GRN]):
        d.ellipse([90 + i * 34, 120, 112 + i * 34, 142], fill=c)
    d.text((220, 116), "forge test — 39 tests in 3 suites, offline, mock system contract + mock callback proxy", font=font(22), fill=DIM)
    f = font(22, mono=True); lh = 29; y = 170
    cmd = "$ forge test"[:cmd_chars]
    d.text((90, y), cmd + ("█" if nlines == 0 else ""), font=f, fill=GRN); y += lh + 6
    WIN = 24  # terminal scrolls: show the last WIN lines
    for l in ft[max(0, nlines - WIN):nlines]:
        c = FG
        if l.startswith("[PASS]"):
            d.text((90, y), "[PASS]", font=f, fill=GRN); d.text((90 + d.textlength("[PASS]", font=f), y), l[6:], font=f, fill=FG)
        else:
            if "Suite result: ok" in l or "39 tests passed" in l: c = GRN
            d.text((90, y), l, font=f, fill=c)
        y += lh
    save(im, name, secs)
cap_t = "forge test: every test is a full local loop: real logs are relayed into react(), and every requested callback is delivered to the vault."
term(0, 12, 1.2, "test_a", cap_t)
steps = [7, 14, 21, 28, 35, 42, len(ft)]
for i, n in enumerate(steps):
    term(n, 12, 1.0 if i < len(steps) - 1 else 6.0, f"test_{i}", cap_t if i < len(steps) - 1 else
         "39/39 passing in 3 suites (core, multichain, admin), including a fuzz test that a forward never exceeds the reported amount or the vault's balance.")

# ---------------------------------------------------------------- loop cards
L = json.load(open(os.path.join(HERE, "loops_decoded.json")))
NAMES = {"0xc1eea4ddd643462402539726a99f1a7ebd50dfe7": "vault", "0x406e7e7fa57f9534c9ce350afa4f23ef0f5faa6c": "marketplace",
         "0xd16be1d20f1ffee777f54bc2f65bd11a710e86c7": "mUSD", "0xc1e54b2522627099ba45936cba066e6ada928993": "main wallet",
         "0xaa14d9cd0f788ca23d11805986c1d8bd035d23b4": "callback proxy", "0x0000000000000000000000000000000000000000": "ETH (native)",
         "0x445c336410f0a49e45893e10c25e39b804f81ba8": "ProceedsReactive"}
def nm(a):
    a = a.lower()
    return NAMES.get(a, a[:6] + "…" + a[-4:])
def amt(v, token):
    v = int(v)
    if token.lower() == "0x0000000000000000000000000000000000000000":
        if v == 0: return "0 ETH"
        return (f"{v / 1e18:.6f}".rstrip("0").rstrip(".") + " ETH") if v >= 10**12 else f"{v} wei"
    return f"{v / 1e6:g} mUSD"
def h32(n): return "0x" + format(int(n), "064x")
REASON = {"0": "Paused", "1": "TokenNotAllowed", "2": "BelowMinimum", "3": "AlreadyProcessed", "4": "NothingToForward", "5": "TransferFailed"}
KIND = {"0": "Transfer route", "1": "Sale route"}

def ev_lines(lg):
    e, a, c = lg["event"], lg.get("args") or {}, lg["contract"]
    if lg["address"].lower() == "0xfffffffffffffffffffffffffffffffffffffffe":
        to = a["to"].lower()
        if to == "0xaa14d9cd0f788ca23d11805986c1d8bd035d23b4":
            return [("callback fee " + f"{int(a['value']) / 1e18:.2e} ETH" + " → proxy", DIM)]
        if a["from"].lower() == "0xaa14d9cd0f788ca23d11805986c1d8bd035d23b4":
            return []
        return [(f"ETH {nm(a['from'])} → {nm(a['to'])}: {amt(a['value'], '0x' + '0' * 40)}", FG)]
    if e == "Transfer":
        return [(f"Transfer {nm(lg['address'])}", ACC), (f"  {nm(a['from'])} → {nm(a['to'])}: {amt(a['value'], lg['address'])}", FG)]
    if e == "Sale":
        return [(f"Sale #{a['listingId']} (marketplace)", ACC), (f"  payee = {nm(a['payee'])}, price {amt(a['price'], a['paymentToken'])}", FG)]
    if e == "NativeReceived":
        return [(f"NativeReceived {amt(a['amount'], '0x' + '0' * 40)}", ACC)]
    if e == "ProceedsDetected":
        return [(f"ProceedsDetected ({KIND.get(a['kind'], a['kind'])})", PUR), (f"  {amt(a['amount'], a['token'])} → {nm(a['vault'])}", FG),
                (f"  origin {h32(a['originTxHash'])[:18]}…", DIM)]
    if e == "ForwardRequested":
        return [("ForwardRequested → callback to vault", PUR)]
    if e == "CallbackReceived":
        return [(f"CallbackReceived {amt(a['reported'], a['token'])}", YEL), (f"  origin {h32(a['originTxHash'])[:18]}…", DIM)]
    if e == "ProceedsForwarded":
        return [(f"ProceedsForwarded {amt(a['amount'], a['token'])}", GRN), (f"  → {nm(a['to'])}, kept {amt(a['kept'], a['token'])}", FG)]
    if e == "ProceedsSkipped":
        return [(f"ProceedsSkipped: {REASON.get(a['reason'], a['reason'])}", YEL), (f"  duplicate of the same origin tx", DIM)]
    if c == "SystemContract":
        return [("system contract log", DIM)]
    return [(f"{c}.{e}", DIM)]

def utc(ts): return datetime.datetime.fromtimestamp(ts, datetime.UTC).strftime("%H:%M:%S UTC")

def loop_slide(key, title, subtitle, stage, caption, secs, name):
    data = L[key]
    im, d = base(caption, title.split(" · ")[0])
    d.text((60, 92), title, font=font(42, True), fill=FG)
    d.text((60, 148), subtitle, font=font(26), fill=DIM)
    cols = [("① Origin event", "Ethereum Sepolia", "origin", GRN, "sepolia.etherscan.io/tx/"),
            ("② Reactive tx", "Reactive Lasna 5318007", "reactive", PUR, "lasna.reactscan.net/tx/"),
            ("③ Callback", "Sepolia · ProceedsVault", "callback", YEL, "sepolia.etherscan.io/tx/")]
    t0 = data["origin"][0]["timestamp"]
    cw, gap, top, bot = 576, 36, 200, 896
    for i, (hd, chain, k, c, url) in enumerate(cols):
        x = 60 + i * (cw + gap)
        on = i < stage
        rr(d, [x, top, x + cw, bot], PANEL if on else (17, 21, 32), c if on else LINE, width=3 if on else 2)
        tc = c if on else LINE; fc = FG if on else (70, 80, 104); dc = DIM if on else (60, 68, 90)
        d.text((x + 22, top + 16), hd, font=font(32, True), fill=tc)
        d.text((x + 22, top + 60), chain, font=font(22), fill=dc)
        y = top + 100
        txs = data[k] if on else []
        if not on:
            d.text((x + 22, y + 10), "waiting…", font=font(26), fill=(70, 80, 104))
        fm = font(18, mono=True); fs = font(21); fsb = font(21, True)
        small = len(txs) > 1
        for t in txs:
            h = t["hash"]
            d.text((x + 22, y), h[:34], font=fm, fill=fc); y += 23
            d.text((x + 22, y), h[34:], font=fm, fill=fc); y += 28
            dt = t["timestamp"] - t0
            st = "success" if t["status"] == 1 else "FAILED"
            d.text((x + 22, y), f"block {t['block']:,} · {utc(t['timestamp'])} (+{dt}s) · {st}", font=font(19), fill=dc); y += 30
            for lg in t["logs"]:
                for (txt, col) in ev_lines(lg):
                    if txt.startswith("  origin") and small: continue
                    d.text((x + 22, y), txt, font=fs if txt.startswith("  ") else fsb, fill=col if on else (70, 80, 104)); y += 27
            y += 12
            d.line([x + 22, y - 6, x + cw - 22, y - 6], fill=LINE, width=1)
        d.text((x + 22, bot - 34), url + "<hash>", font=font(18, mono=True), fill=dc)
        if i < 2:
            ax = x + cw + 4; ay = 540
            d.polygon([(ax, ay - 16), (ax + 28, ay), (ax, ay + 16)], fill=c if i + 1 < stage else LINE)
    d.text((60, 906), "Decoded from eth_getTransactionReceipt on Sepolia and Lasna RPC; full links in the README.", font=font(20), fill=(110, 120, 150))
    save(im, name, secs)

loops = [
    ("loop2-direct", "Loop 2 · direct payment", "Someone pays 25 mUSD straight to the vault (rule: min 5, keep 1)",
     ["A plain ERC20 transfer of 25 mUSD lands in the vault on Sepolia. That Transfer log is all we need.",
      "Same second on Lasna: ProceedsReactive matched the subscription, emitted ProceedsDetected and requested a callback.",
      "One Sepolia block later the vault forwards 24 mUSD to the main wallet and keeps 1. About 12 seconds end to end."]),
    ("loop3-tokenSale", "Loop 3 · marketplace sale in mUSD", "A 40 mUSD sale pays the vault: both the Transfer route and the Sale route fire",
     ["A marketplace sale pays 40 mUSD to the vault. One tx emits two matching logs: an ERC20 Transfer and a Sale.",
      "So Lasna runs two reactive txs, one per route, and requests two callbacks for the same origin tx.",
      "The vault forwards 39 mUSD exactly once; the second callback is skipped as AlreadyProcessed. No double spend."]),
    ("loop4-nativeSale", "Loop 4 · marketplace sale in ETH", "A 0.0002 ETH sale pays the vault in native currency",
     ["A sale paid in native ETH: the marketplace sends 0.0002 ETH to the vault and emits Sale with token = 0x0.",
      "The Sale route matches on Lasna and requests a callback carrying the native token and amount.",
      "The vault forwards the 0.0002 ETH but never touches its gas buffer; it also pays the tiny callback fee itself."]),
]
for key, title, sub, caps in loops:
    for s in (1, 2, 3):
        loop_slide(key, title, sub, s, caps[s - 1], 6.0 if s < 3 else 8.0, f"{key}_s{s}")

# ---------------------------------------------------------------- results table
im, d = base("Five full loops on testnet. Loop 1 ran out of gas at a 500k callback limit; one owner call raised it to 1M, and every loop after it worked.", "Results")
d.text((60, 100), "All five on-chain loops", font=font(44, True), fill=FG)
rows = [("1", "direct 25 mUSD, gas limit 500k", "CallbackFailure (out of gas) → setCallbackGasLimit(1M)", RED),
        ("2", "direct 25 mUSD", "forwarded 24 mUSD, kept 1", GRN),
        ("3", "marketplace sale 40 mUSD", "forwarded 39 mUSD once, duplicate skipped", GRN),
        ("4", "marketplace sale 0.0002 ETH", "forwarded 0.0002 ETH, gas buffer intact", GRN),
        ("5", "dust payment 2 mUSD (< min 5)", "skipped: BelowMinimum, funds stay in vault", YEL)]
y = 190
rr(d, [60, y, 1860, y + 64], PANEL2)
for x, t in [(90, "#"), (170, "Scenario"), (820, "Result on the vault")]:
    d.text((x, y + 16), t, font=font(28, True), fill=DIM)
y += 80
for n, s, r, c in rows:
    rr(d, [60, y, 1860, y + 96], PANEL, c, width=2)
    d.text((95, y + 28), n, font=font(34, True), fill=c)
    d.text((170, y + 30), s, font=font(30), fill=FG)
    d.text((820, y + 30), r, font=font(30, True), fill=c)
    y += 112
d.text((60, y + 10), "Cost per callback on Sepolia ≈ 3·10⁻¹¹ ETH, paid by the vault; ≈ 0.013 lREACT per reactive tx on Lasna.", font=font(26), fill=DIM)
save(im, "results", 11)

# ---------------------------------------------------------------- verification
im, d = base("All four contracts are source-verified on Sourcify, the verifier Reactive's docs point to for Lasna.", "Verified")
d.text((60, 100), "Source-verified on Sourcify", font=font(44, True), fill=FG)
ver = [("ProceedsReactive", "Lasna 5318007", "0x445C336410F0A49e45893e10c25E39B804F81BA8"),
       ("ProceedsVault", "Sepolia 11155111", "0xc1EEA4ddD643462402539726a99F1a7Ebd50dFE7"),
       ("MockMarketplace", "Sepolia 11155111", "0x406e7E7FA57f9534C9Ce350Afa4f23eF0F5faA6c"),
       ("MockUSD", "Sepolia 11155111", "0xd16Be1D20f1FFee777F54BC2F65bD11A710E86c7")]
y = 190
for n, ch, a in ver:
    rr(d, [60, y, 1860, y + 150], PANEL, GRN, width=2)
    d.text((95, y + 20), "✓ " + n, font=font(34, True), fill=GRN)
    d.text((620, y + 26), ch, font=font(28), fill=DIM)
    d.text((95, y + 84), f"repo.sourcify.dev/{ch.split()[-1]}/{a}", font=font(26, mono=True), fill=FG)
    y += 170
save(im, "verified", 8)

# ---------------------------------------------------------------- second chain: Base Sepolia
im, d = base("The same ProceedsReactive on Lasna also serves a vault on Base Sepolia: no redeploy, just two watch calls. Callbacks land in 1–2 s there vs 12 s on Sepolia.", "Second chain")
d.text((60, 100), "Second chain · Base Sepolia (84532)", font=font(44, True), fill=FG)
d.text((60, 160), "Same reactive contract 0x445C…1BA8 on Lasna · new vault 0x1409…eb10 · 3 live loops, all as intended", font=font(26), fill=DIM)
LAT = [l.rstrip("\n").split("\t") for l in open(os.path.join(ROOT, "runs", "latency.tsv"))][1:]
brow = {"base1-direct": "direct 25 mUSD → forwarded 24, kept 1",
        "base2-tokenSale": "sale 40 mUSD → forwarded 39 once, duplicate skipped",
        "base3-nativeSale": "sale in ETH → forwarded 0.0000475 ETH"}
y = 220
for r in LAT:
    if r[0] not in brow: continue
    rr(d, [60, y, 1860, y + 84], PANEL, GRN, width=2)
    d.text((95, y + 24), r[0], font=font(28, True), fill=GRN)
    d.text((470, y + 24), brow[r[0]], font=font(28), fill=FG)
    d.text((1560, y + 24), f"{r[7]} s end to end", font=font(28, True), fill=ACC)
    y += 100
y += 20
d.text((60, y), "Origin event → callback on the destination chain (block timestamps)", font=font(30, True), fill=FG); y += 60
sep = [int(r[7]) for r in LAT if r[1] == "Sepolia"]; bs = [int(r[7]) for r in LAT if r[1] == "Base Sepolia"]
for lbl, vals, c in [("Ethereum Sepolia · 5 loops", sep, YEL), ("Base Sepolia · 3 loops", bs, GRN)]:
    d.text((60, y + 10), lbl, font=font(28), fill=c)
    w = int(1200 * max(vals) / 12)
    rr(d, [520, y, 520 + w, y + 54], c, r=10)
    t = f"{min(vals)}–{max(vals)} s" if min(vals) != max(vals) else f"{max(vals)} s"
    d.text((540 + w, y + 10), t, font=font(30, True), fill=c)
    y += 80
save(im, "base", 16)

# ---------------------------------------------------------------- closing
im, d = base()
d.text((140, 260), "Set it and forget it.", font=font(84, True), fill=FG)
d.text((144, 380), "Point your payout address at a vault. Reactive Network does the rest.", font=font(38), fill=ACC)
ys = 480
for t in ["• One reactive contract serves vaults on Sepolia and Base Sepolia (live), more chains by config",
          "• Owner rules: allowlist · minimum · keep · gas buffer · pause · sweep · public coverDebt()",
          "• 39 tests · 8 live loops on Sepolia + Base Sepolia · every tx linked in the README",
          "• github.com/gmlokie/proceeds-auto-forward"]:
    d.text((144, ys), t, font=font(32), fill=FG); ys += 62
save(im, "closing", 7)

json.dump(segments, open(os.path.join(HERE, "segments.json"), "w"), indent=1)
print("frames", len(segments), "total", sum(s for _, s in segments))
