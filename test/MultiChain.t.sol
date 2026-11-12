// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {ProceedsVault} from "../src/destination/ProceedsVault.sol";
import {ProceedsReactive} from "../src/reactive/ProceedsReactive.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";
import {MockSystem, MockCallbackProxy} from "./utils/Mocks.sol";

/// @notice One reactive contract serving two chains at once (Ethereum Sepolia + Base Sepolia), the way
///         the live deployment runs: each chain has its own vault, token and callback proxy, and every
///         event is routed back to the vault on the chain where the money actually is.
contract MultiChainRoutingTest is Test {
    address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 constant SEPOLIA = 11155111;
    uint256 constant BASE_SEPOLIA = 84532;

    MockSystem sys;
    ProceedsReactive rc;

    // "Sepolia side"
    MockCallbackProxy proxyA;
    ProceedsVault vaultA;
    MockUSD usdA;
    // "Base Sepolia side"
    MockCallbackProxy proxyB;
    ProceedsVault vaultB;
    MockUSD usdB;

    address main = makeAddr("coldMainWallet");

    function setUp() public {
        vm.etch(SYSTEM_ADDR, address(new MockSystem()).code);
        sys = MockSystem(payable(SYSTEM_ADDR));
        rc = new ProceedsReactive(1_000_000);

        proxyA = new MockCallbackProxy();
        proxyB = new MockCallbackProxy();
        usdA = new MockUSD();
        usdB = new MockUSD();
        vaultA = new ProceedsVault(IPayable(payable(address(proxyA))), address(rc), main, 0);
        vaultB = new ProceedsVault(IPayable(payable(address(proxyB))), address(rc), main, 0);
        vaultA.setTokenRule(address(usdA), true, 5e6, 1e6);
        vaultB.setTokenRule(address(usdB), true, 5e6, 1e6);

        rc.watchToken(SEPOLIA, address(usdA), address(vaultA));
        rc.watchToken(BASE_SEPOLIA, address(usdB), address(vaultB));
    }

    function _transferLog(uint256 chainId, address token, address to, uint256 value, uint256 txHash)
        internal
        pure
        returns (IReactive.LogRecord memory r)
    {
        r.chainId = chainId;
        r.contractAddress = token;
        r.topic0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
        r.topic1 = uint256(uint160(address(0xBEEF)));
        r.topic2 = uint256(uint160(to));
        r.data = abi.encode(value);
        r.opCode = 3;
        r.txHash = txHash;
    }

    function _react(IReactive.LogRecord memory r) internal {
        vm.prank(SYSTEM_ADDR);
        rc.react(r);
    }

    function _last() internal view returns (ISystemContract.CallbackConfiguration_V_1_0 memory) {
        return sys.callbackAt(sys.callbackCount() - 1);
    }

    function test_SubscribesOnBothOriginChains() public view {
        assertEq(sys.subCount(), 2);
        (uint256 c0, address s0,,, uint256 t20,, bool a0) = sys.subs(0);
        (uint256 c1, address s1,,, uint256 t21,, bool a1) = sys.subs(1);
        assertEq(c0, SEPOLIA);
        assertEq(s0, address(usdA));
        assertEq(t20, uint256(uint160(address(vaultA))));
        assertEq(c1, BASE_SEPOLIA);
        assertEq(s1, address(usdB));
        assertEq(t21, uint256(uint160(address(vaultB))));
        assertTrue(a0 && a1);
        assertTrue(rc.isVault(SEPOLIA, address(vaultA)));
        assertTrue(rc.isVault(BASE_SEPOLIA, address(vaultB)));
    }

    function test_EachChainCallsBackToItsOwnVault() public {
        _react(_transferLog(BASE_SEPOLIA, address(usdB), address(vaultB), 30e6, 0xb1));
        ISystemContract.CallbackConfiguration_V_1_0 memory cb = _last();
        assertEq(cb.chainId, BASE_SEPOLIA);
        assertEq(cb.recipient, address(vaultB));
        assertEq(cb.gasLimit, 1_000_000);

        _react(_transferLog(SEPOLIA, address(usdA), address(vaultA), 30e6, 0xa1));
        cb = _last();
        assertEq(cb.chainId, SEPOLIA);
        assertEq(cb.recipient, address(vaultA));
        assertEq(sys.callbackCount(), 2);
    }

    function test_BaseSepoliaLoopForwardsThroughItsOwnProxy() public {
        usdB.mint(address(vaultB), 30e6); // the payment that emitted the log
        _react(_transferLog(BASE_SEPOLIA, address(usdB), address(vaultB), 30e6, 0xb2));
        ISystemContract.CallbackConfiguration_V_1_0 memory cb = _last();

        // Delivered by the wrong chain's proxy: rejected by the vault's proxy check.
        (bool okWrong,) = proxyA.deliver(cb.recipient, cb.payload, address(rc));
        assertFalse(okWrong);
        // Delivered by Base Sepolia's proxy: forwarded minus keep.
        (bool ok,) = proxyB.deliver(cb.recipient, cb.payload, address(rc));
        assertTrue(ok);
        assertEq(usdB.balanceOf(main), 29e6);
        assertEq(usdB.balanceOf(address(vaultB)), 1e6);
    }

    function test_VaultRegisteredOnOneChainIsIgnoredOnTheOther() public {
        // Same address as vaultA, but the event happened on Base Sepolia, where it is not registered.
        uint256 before = sys.callbackCount();
        _react(_transferLog(BASE_SEPOLIA, address(usdA), address(vaultA), 30e6, 0xc1));
        assertEq(sys.callbackCount(), before);
        assertFalse(rc.isVault(BASE_SEPOLIA, address(vaultA)));
    }

    function test_DedupeKeyIncludesOriginChain() public {
        // Two callbacks with the same tx hash but different origin chains are distinct payments.
        usdA.mint(address(vaultA), 40e6);
        bytes memory p1 =
            abi.encodeCall(ProceedsVault.onProceeds, (address(0), SEPOLIA, address(usdA), 20e6, 0xdead));
        bytes memory p2 = abi.encodeCall(
            ProceedsVault.onProceeds, (address(0), BASE_SEPOLIA, address(usdA), 20e6, 0xdead)
        );
        proxyA.deliver(address(vaultA), p1, address(rc));
        proxyA.deliver(address(vaultA), p2, address(rc));
        proxyA.deliver(address(vaultA), p1, address(rc)); // true replay: skipped
        assertEq(usdA.balanceOf(main), 38e6);
    }

    function test_UnwatchOneChainKeepsTheOther() public {
        rc.unwatchToken(BASE_SEPOLIA, address(usdB), address(vaultB));
        assertFalse(rc.isVault(BASE_SEPOLIA, address(vaultB)));
        assertTrue(rc.isVault(SEPOLIA, address(vaultA)));

        uint256 before = sys.callbackCount();
        _react(_transferLog(BASE_SEPOLIA, address(usdB), address(vaultB), 30e6, 0xd1));
        assertEq(sys.callbackCount(), before);
        _react(_transferLog(SEPOLIA, address(usdA), address(vaultA), 30e6, 0xd2));
        assertEq(sys.callbackCount(), before + 1);
    }
}
