#!/usr/bin/env bash
# Runs one origin action on an origin chain and follows it through Reactive Lasna back to the vault callback
# on the same chain. Works for Ethereum Sepolia (default) and Base Sepolia.
# Usage: source .env.sh && ACTION=direct|tokenSale|nativeSale|dust [ORIGIN_RPC=$BASE_SEPOLIA_RPC] script/loop.sh <label>
# Appends one row to runs/loops.tsv (label, origin tx, reactive tx(s), callback tx(s), origin chain id).
set -euo pipefail
: "${REACTIVE:?}" "${VAULT:?}" "${TOKEN:?}" "${MARKET:?}" "${ACTION:?}"
ORIGIN_RPC=${ORIGIN_RPC:-$SEPOLIA_RPC}
LABEL=${1:-$ACTION}
DETECTED=$(cast sig-event "ProceedsDetected(uint256,address,address,uint256,uint8,uint256)")
RECEIVED=$(cast sig-event "CallbackReceived(uint256,uint256,address,uint256)")
CHAIN=$(cast chain-id --rpc-url "$ORIGIN_RPC")

# Fee: ~2x current base fee + small tip (testnets are nearly free; never overpay).
BASE_FEE=$(cast base-fee --rpc-url "$ORIGIN_RPC")
TIP=${TIP_WEI:-1000}
MAXFEE=$((BASE_FEE * 2 + TIP))

LASNA_FROM=$(cast block-number --rpc-url "$LASNA_RPC")
forge script script/Demo.s.sol --rpc-url "$ORIGIN_RPC" --private-key "$PRIVATE_KEY" --broadcast \
  --with-gas-price "$MAXFEE" --priority-gas-price "$TIP" >/dev/null
mkdir -p runs && cp "broadcast/Demo.s.sol/$CHAIN/run-latest.json" "runs/$LABEL.json"
ORIGIN_TX=$(jq -r '.receipts[-1].transactionHash' "runs/$LABEL.json")
ORIGIN_BLK=$(jq -r '.receipts[-1].blockNumber' "runs/$LABEL.json")
echo "origin   $ORIGIN_TX (chain $CHAIN)"

# 1) reactive tx on Lasna: ProceedsDetected whose last data word is the origin tx hash
RTX=""
for _ in $(seq 1 60); do
  RTX=$(cast logs --address "$REACTIVE" "$DETECTED" --from-block "$LASNA_FROM" --rpc-url "$LASNA_RPC" --json \
    | jq -r --arg h "${ORIGIN_TX#0x}" '[.[]|select(.data|endswith($h))|.transactionHash]|join(",")')
  [ -n "$RTX" ] && break; sleep 4
done
echo "reactive $RTX"

# 2) callback tx on the origin chain: vault CallbackReceived with topic2 = origin tx hash
CTX=""
for _ in $(seq 1 60); do
  CTX=$(cast logs --address "$VAULT" "$RECEIVED" --from-block "$((ORIGIN_BLK))" --rpc-url "$ORIGIN_RPC" --json \
    | jq -r --arg h "$ORIGIN_TX" '[.[]|select(.topics[2]==$h)|.transactionHash]|unique|join(",")')
  [ -n "$CTX" ] && break; sleep 4
done
echo "callback $CTX"
printf '%s\t%s\t%s\t%s\t%s\n' "$LABEL" "$ORIGIN_TX" "$RTX" "$CTX" "$CHAIN" >> runs/loops.tsv
