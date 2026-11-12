# STATUS — Proceeds Auto-Forward (Reactive Omni Buildathon, "Set It and Forget It")

Updated: 2026-11-12 ~15:10 WIB. Deadline: 2026-12-05 20:00 UTC (2026-12-06 03:00 WIB).

## Done
- Foundry project, Solidity 0.8.29, reactive-lib-omni v0.1.0 (Omni: no RVM, plain deploy on Lasna).
- Contracts: `ProceedsReactive` (Lasna), `ProceedsVault` (Sepolia, AbstractCallback), `MockMarketplace`, `MockUSD`.
- `forge test`: 21/21 passing (incl. fuzz), full local loop via mock system contract + mock callback proxy.
- Deployed on testnets and ran 5 full loops (event → reactive tx → callback); 4 succeeded as intended
  (2 forwards of mUSD, 1 ETH forward, 1 BelowMinimum skip, plus a dedupe skip), loop 1 hit
  CallbackFailure (out of gas at a 500k callback gas limit) and was fixed by raising the limit to 1M.
- README with mermaid diagrams, setup, addresses, tx table. Local git repo committed. No GitHub repo created, nothing posted.

## Addresses
| Contract | Chain | Address |
| --- | --- | --- |
| ProceedsReactive | Lasna 5318007 | 0x445C336410F0A49e45893e10c25E39B804F81BA8 |
| ProceedsVault | Sepolia 11155111 | 0xc1EEA4ddD643462402539726a99F1a7Ebd50dFE7 |
| MockMarketplace | Sepolia | 0x406e7E7FA57f9534C9Ce350Afa4f23eF0F5faA6c |
| MockUSD | Sepolia | 0xd16Be1D20f1FFee777F54BC2F65bD11A710E86c7 |
| Owner / deployer / demo main wallet | both | 0xc1e54b2522627099ba45936CBa066e6adA928993 (testnet burner) |

Explorers: https://lasna.reactscan.net/address/0x445C336410F0A49e45893e10c25E39B804F81BA8 ·
https://sepolia.etherscan.io/address/0xc1EEA4ddD643462402539726a99F1a7Ebd50dFE7

## Setup txs
- Faucet (0.006 Sepolia ETH → 0.63 lREACT): 0x64440492d2b513244dcdae1ee752c318fc7c0031986bc2535a260e43c5fba2d2 (Sepolia)
- Deploy ProceedsReactive (funded 0.2 lREACT): 0x516011eecd0a64aee597c52cbb414494ea140e56ffb26996c1de6582f18dd6db (Lasna)
- Deploy MockUSD 0x4404b59554b60f0f73319f04eafb51f8c78437b3e782f8e639964f2a2f23fae2, MockMarketplace 0x972c9707df7dd972ce55cdd256bc0b13f61d5edea562aa0dbc5a4ea46a2f79cd, ProceedsVault 0x564e5b65c0852d761ab9fe834354a9455d562c462dbe4e7f92a7f543521dee3a, rules 0xd61b11d5…5441 / 0x892a98ba…9ce7 (Sepolia)
- watchToken 0x653ab25cc6280eb39b1ca157ecdefa40c1babdb3cb92c0d58cc07f02417594fc, watchMarketplace 0xfc308784089516e78d91b2bcd4b7335f5283b4bb13efd4f21840d1356431557f (Lasna)
- setCallbackGasLimit(1M) 0x6857888679e223f6e68cfee9f2eabb299d4235bfb10a41c285a22514ba8ca208 (Lasna)
- Vault: setNativeGasBuffer(0.00001 ETH) 0xd2361217ab0cd0c2a127478a3df16f3fa510f44a6b48fc3ce7dedc971ba9dbfb, sweep 0.00049 ETH back to burner 0x9d4acb726b0850e304777198fe705a30b542f6e739dd51f0c15030a7e6ccf209 (Sepolia)

## Loops (origin Sepolia → reactive Lasna → callback Sepolia) — also in runs/loops.tsv
| # | Scenario | Origin | Reactive | Callback | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | direct 25 mUSD, gas limit 500k | 0xe9aa95ef54686ff8c0be62243aad641f956295f9ea0b9adc086ae289cb0db921 | 0x2e2a60a4ca94080c1dc2178f34ce42ac010e928c93aafdd7000730da2a852d3f | 0x6917efaa098493ddba23295fb673af7e9a24f27d2a974d0b9c1a168bd736afb8 | CallbackFailure (OOG) |
| 2 | direct 25 mUSD | 0xdc8a5be179ad50bef4bd686599e9eb035cf44139cdd93b3a997bc2924c29a9e7 | 0x1482bb472585490347f3cbfe587a37c2c3164efb9695c15c89f66a7984196ea2 | 0xedb849ec2b8cb7ca9f23b67c2c6fba791432944a00587bc6e44aa603f1a79705 | forwarded 24 mUSD, kept 1 |
| 3 | marketplace sale 40 mUSD | 0x04d96024c32be76dcf0a8eb574bba84b0e1043cd8b357660db56aa9a4e52178f | 0x17efa5d1113bfab7fcb266684b64a79593cc23da41374590223cf4ccf79f2b1b, 0x6ce056117d98526afc3a188bc83ac6fa325670f575fceec6bb7ba308bc52c84c | 0xd8f5309d32eb35ed194e53733dc8f716eb7b1cc357c14bd45e4a17914afee775 (forward), 0x09fad7a457754b6f86aadb3d07e7375d2f6a81f6c590960d3fd32c6fe7733569 (dup skip) | forwarded 39 mUSD once |
| 4 | marketplace sale 0.0002 ETH | 0xe5c4c5ffc4dd22a3af2b41092945311d5ebf8368c2a2fd1f86961bebf5c52d8e | 0x44cc6bd43e057d7e7a103484e745817a4e73d832700ad52519e082d3f7132e35 | 0x1d29a5a9d1a45f7179a88b0eb254ba4d83ba23ab911bdeb11c72e483b8916aff | forwarded 0.0002 ETH |
| 5 | dust 2 mUSD | 0x48d3a5df11cab7dff80eda3a6aced7e5cdd6b446267c5def77c4f2d9a5b06261 | 0x6a57797e55974b9704528adb1428e72c876e366c3398e4f84221bc56c0a13776 | 0x0529adfa2c81ea93ae691ab87d27d304878b6f93336675f01770a63b0a33c1f8 | skipped BelowMinimum |

Links: Sepolia `https://sepolia.etherscan.io/tx/<hash>`, Lasna `https://lasna.reactscan.net/tx/<hash>`.

## Balances after the run
- Burner Sepolia ETH: 0.00316 (start 0.01241). Spent: 0.006 faucet + ~0.0034 gas (Sepolia contract creation is very
  gas-heavy now: vault deploy ~7.8M gas; I used 0.2 gwei when base fee was ~19 wei, which overpaid). It briefly dipped to
  0.00267 (< 0.003 floor) after the loops; I swept 0.00049 ETH of unneeded vault funding back to restore it.
- Burner Lasna: 0.31 lREACT. ProceedsReactive: 0.12 lREACT, debt 0. Vault: 0.00001 ETH (enough for hundreds of callbacks at
  ~3e-11 ETH each), 29 mUSD left inside (25 from failed loop 1, 2 dust, 2×1 keep).
- No mainnet tx, no mainnet approvals, no bridging. Only testnet MockUSD approve to MockMarketplace on Sepolia.

## Blockers / open items
- None blocking. Optional polish before submitting:
  - Verify contracts (Sourcify on Lasna via `forge verify-contract --verifier sourcify --chain-id 5318007`; Etherscan on
    Sepolia needs an API key). Note: the deployed MockUSD/MockMarketplace were compiled against OZ master at that moment;
    the repo now pins OZ v5.4.0 as a submodule, so their bytecode may not match exactly. Vault and reactive only use
    OZ `IERC20` (interface), so they should match.
  - Demo video / screenshots of reactscan + etherscan for DoraHacks.
  - Push to a public GitHub repo and submit on DoraHacks (not done, per instructions).
  - Optional: a second destination (Base Sepolia / Unichain Sepolia) to show one reactive contract serving many chains;
    needs testnet ETH on those chains (burner has 0 there).
