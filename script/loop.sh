#!/usr/bin/env bash
# Runs one origin action on Sepolia and follows it through Reactive Lasna back to the vault callback.
# Usage: source .env.sh && ACTION=direct|tokenSale|nativeSale|dust script/loop.sh <label>
set -euo pipefail
: "${REACTIVE:?}" "${VAULT:?}" "${TOKEN:?}" "${MARKET:?}" "${ACTION:?}"
LABEL=${1:-$ACTION}
SYS=0x8888888888888888888888888888888888888888
DETECTED=$(cast sig-event "ProceedsDetected(uint256,address,address,uint256,uint8,uint256)")
RECEIVED=$(cast sig-event "CallbackReceived(uint256,uint256,address,uint256)")

LASNA_FROM=$(cast block-number --rpc-url "$LASNA_RPC")
forge script script/Demo.s.sol --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" --broadcast --legacy \
  --with-gas-price 0.2gwei >/dev/null
mkdir -p runs && cp broadcast/Demo.s.sol/11155111/run-latest.json "runs/$LABEL.json"
ORIGIN_TX=$(jq -r '.receipts[-1].transactionHash' "runs/$LABEL.json")
ORIGIN_BLK=$(jq -r '.receipts[-1].blockNumber' "runs/$LABEL.json")
echo "origin   $ORIGIN_TX"

# 1) reactive tx on Lasna: ProceedsDetected whose last data word is the origin tx hash
RTX=""
for _ in $(seq 1 40); do
  RTX=$(cast logs --address "$REACTIVE" "$DETECTED" --from-block "$LASNA_FROM" --rpc-url "$LASNA_RPC" --json \
    | jq -r --arg h "${ORIGIN_TX#0x}" '[.[]|select(.data|endswith($h))|.transactionHash]|join(",")')
  [ -n "$RTX" ] && break; sleep 6
done
echo "reactive $RTX"

# 2) callback tx on Sepolia: vault CallbackReceived with topic2 = origin tx hash
CTX=""
for _ in $(seq 1 40); do
  CTX=$(cast logs --address "$VAULT" "$RECEIVED" --from-block "$((ORIGIN_BLK))" --rpc-url "$SEPOLIA_RPC" --json \
    | jq -r --arg h "$ORIGIN_TX" '[.[]|select(.topics[2]==$h)|.transactionHash]|unique|join(",")')
  [ -n "$CTX" ] && break; sleep 6
done
echo "callback $CTX"
printf '%s\t%s\t%s\t%s\n' "$LABEL" "$ORIGIN_TX" "$RTX" "$CTX" >> runs/loops.tsv
