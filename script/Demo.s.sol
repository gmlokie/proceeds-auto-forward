// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console2} from "forge-std/Script.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";
import {MockMarketplace} from "../src/mocks/MockMarketplace.sol";

/// Origin-side demo actions on Sepolia. Each one is a single origin event that kicks off the loop.
///   ACTION=direct|tokenSale|nativeSale|dust TOKEN=.. MARKET=.. VAULT=.. forge script script/Demo.s.sol \
///     --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast
contract Demo is Script {
    function run() external {
        string memory action = vm.envString("ACTION");
        MockUSD usd = MockUSD(vm.envAddress("TOKEN"));
        MockMarketplace market = MockMarketplace(vm.envAddress("MARKET"));
        address vault = vm.envAddress("VAULT");
        bytes32 a = keccak256(bytes(action));

        vm.startBroadcast();
        address me = msg.sender;
        if (a == keccak256("direct")) {
            // A customer pays an invoice straight into the vault: 25 mUSD.
            usd.mint(me, 25e6);
            usd.transfer(vault, 25e6);
        } else if (a == keccak256("tokenSale")) {
            // An item sells on the marketplace for 40 mUSD with the vault as payee.
            usd.mint(me, 40e6);
            usd.approve(address(market), 40e6);
            uint256 id = market.list(vault, address(usd), 40e6);
            market.buy(id);
        } else if (a == keccak256("nativeSale")) {
            uint256 price = vm.envOr("PRICE", uint256(0.0002 ether));
            uint256 id = market.list(vault, address(0), price);
            market.buy{value: price}(id);
        } else if (a == keccak256("dust")) {
            // Below the 5 mUSD minimum: the vault should skip it.
            usd.mint(me, 2e6);
            usd.transfer(vault, 2e6);
        } else {
            revert("unknown ACTION");
        }
        vm.stopBroadcast();
        console2.log("done", action);
    }
}
