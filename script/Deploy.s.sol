// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console2} from "forge-std/Script.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {ProceedsVault} from "../src/destination/ProceedsVault.sol";
import {ProceedsReactive} from "../src/reactive/ProceedsReactive.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";
import {MockMarketplace} from "../src/mocks/MockMarketplace.sol";

/// Step 1 — Reactive Lasna. Deploys ProceedsReactive funded with REACTIVE_FUNDING (wei, default 0.1 lREACT).
///   forge script script/Deploy.s.sol:DeployReactive --rpc-url $LASNA_RPC --private-key $PRIVATE_KEY --broadcast
contract DeployReactive is Script {
    function run() external returns (ProceedsReactive rc) {
        uint256 funding = vm.envOr("REACTIVE_FUNDING", uint256(0.1 ether));
        uint64 gasLimit = uint64(vm.envOr("CALLBACK_GAS_LIMIT", uint256(1_000_000)));
        vm.startBroadcast();
        rc = new ProceedsReactive{value: funding}(gasLimit);
        vm.stopBroadcast();
        console2.log("ProceedsReactive", address(rc));
    }
}

/// Step 2 — destination chain (Sepolia). Deploys the vault bound to the reactive contract, plus the
/// demo token + marketplace, and sets owner rules.
///   REACTIVE=0x.. MAIN_WALLET=0x.. forge script script/Deploy.s.sol:DeployDestination \
///     --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast
contract DeployDestination is Script {
    function run() external returns (ProceedsVault vault, MockUSD usd, MockMarketplace market) {
        address proxy = vm.envOr("CALLBACK_PROXY", address(0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4));
        address reactive = vm.envAddress("REACTIVE");
        address mainWallet = vm.envAddress("MAIN_WALLET");
        uint256 gasBuffer = vm.envOr("NATIVE_GAS_BUFFER", uint256(0.00001 ether));
        uint256 funding = vm.envOr("VAULT_FUNDING", uint256(0.00001 ether));

        vm.startBroadcast();
        usd = new MockUSD();
        market = new MockMarketplace();
        vault = new ProceedsVault{value: funding}(IPayable(payable(proxy)), reactive, mainWallet, gasBuffer);
        vault.setTokenRule(address(usd), true, 5e6, 1e6); // min 5 mUSD, keep 1 mUSD per forward
        vault.setTokenRule(address(0), true, 0.00001 ether, 0); // native: min 0.00001 ETH
        vm.stopBroadcast();

        console2.log("MockUSD        ", address(usd));
        console2.log("MockMarketplace", address(market));
        console2.log("ProceedsVault  ", address(vault));
    }
}

/// Step 3 — Reactive Lasna. Subscribes the reactive contract to the token and marketplace routes.
///   REACTIVE=.. ORIGIN_CHAIN_ID=11155111 TOKEN=.. MARKET=.. VAULT=.. forge script \
///     script/Deploy.s.sol:ConfigureRoutes --rpc-url $LASNA_RPC --private-key $PRIVATE_KEY --broadcast
contract ConfigureRoutes is Script {
    function run() external {
        ProceedsReactive rc = ProceedsReactive(payable(vm.envAddress("REACTIVE")));
        uint256 chainId = vm.envOr("ORIGIN_CHAIN_ID", uint256(11155111));
        address vault = vm.envAddress("VAULT");
        vm.startBroadcast();
        rc.watchToken(chainId, vm.envAddress("TOKEN"), vault);
        rc.watchMarketplace(chainId, vm.envAddress("MARKET"), vault);
        vm.stopBroadcast();
    }
}
