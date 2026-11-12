// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, Vm} from "forge-std/Test.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {AbstractPayer} from "@reactive/src/base/AbstractPayer.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {ProceedsVault} from "../src/destination/ProceedsVault.sol";
import {ProceedsReactive} from "../src/reactive/ProceedsReactive.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";
import {MockMarketplace} from "../src/mocks/MockMarketplace.sol";
import {MockSystem, MockCallbackProxy} from "./utils/Mocks.sol";

/// @notice End-to-end loop on one local chain: origin event -> react() -> callback request -> proxy
///         delivery -> vault forwards to the main wallet. The network is simulated by MockSystem and
///         MockCallbackProxy; everything else is the production code.
contract ProceedsAutoForwardTest is Test {
    address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;

    MockSystem sys;
    MockCallbackProxy proxy;
    ProceedsReactive rc;
    ProceedsVault vault;
    MockUSD usd;
    MockMarketplace market;

    address main = makeAddr("mainWallet");
    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    uint256 constant GAS_BUFFER = 0.001 ether;

    function setUp() public {
        vm.etch(SYSTEM_ADDR, address(new MockSystem()).code);
        sys = MockSystem(payable(SYSTEM_ADDR));
        proxy = new MockCallbackProxy();

        rc = new ProceedsReactive(500_000);
        vault = new ProceedsVault(IPayable(payable(address(proxy))), address(rc), main, GAS_BUFFER);
        usd = new MockUSD();
        market = new MockMarketplace();

        vault.setTokenRule(address(usd), true, 5e6, 1e6); // min 5 mUSD, keep 1 mUSD
        vault.setTokenRule(address(0), true, 0.0001 ether, 0); // native allowed

        rc.watchToken(block.chainid, address(usd), address(vault));
        rc.watchMarketplace(block.chainid, address(market), address(vault));

        usd.mint(buyer, 1_000e6);
        vm.deal(buyer, 1 ether);
        vm.deal(address(vault), GAS_BUFFER);
        vm.prank(buyer);
        usd.approve(address(market), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers

    /// @dev Turns recorded EVM logs into LogRecords, feeds those matching our subscriptions to react(),
    ///      then delivers every resulting callback through the proxy.
    function _relay() internal returns (uint256 delivered) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 before = sys.callbackCount();
        for (uint256 i; i < logs.length; ++i) {
            if (!_subscribed(logs[i])) continue;
            vm.prank(SYSTEM_ADDR);
            rc.react(_toRecord(logs[i], i));
        }
        for (uint256 j = before; j < sys.callbackCount(); ++j) {
            ISystemContract.CallbackConfiguration_V_1_0 memory cb = sys.callbackAt(j);
            assertEq(cb.chainId, block.chainid);
            (bool ok,) = proxy.deliver(cb.recipient, cb.payload, address(rc));
            assertTrue(ok, "callback reverted");
            delivered++;
        }
    }

    function _subscribed(Vm.Log memory l) internal view returns (bool) {
        uint256 n = sys.subCount();
        for (uint256 i; i < n; ++i) {
            (uint256 c, address s, uint256 t0,, uint256 t2,, bool active) = sys.subs(i);
            if (!active || c != block.chainid || s != l.emitter || l.topics.length < 3) continue;
            if (uint256(l.topics[0]) == t0 && uint256(l.topics[2]) == t2) return true;
        }
        return false;
    }

    function _toRecord(Vm.Log memory l, uint256 idx) internal view returns (IReactive.LogRecord memory r) {
        r.chainId = block.chainid;
        r.contractAddress = l.emitter;
        r.topic0 = uint256(l.topics[0]);
        r.topic1 = l.topics.length > 1 ? uint256(l.topics[1]) : 0;
        r.topic2 = l.topics.length > 2 ? uint256(l.topics[2]) : 0;
        r.topic3 = l.topics.length > 3 ? uint256(l.topics[3]) : 0;
        r.data = l.data;
        r.opCode = l.topics.length;
        r.blockNumber = block.number;
        r.txHash = uint256(keccak256(abi.encode("tx", block.number, vm.getNonce(buyer))));
        r.logIndex = idx;
    }

    /// @dev Looks for the vault's ProceedsSkipped event (with `reason`) among logs emitted during delivery.
    function _assertSkipped(ProceedsVault.SkipReason reason) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter != address(vault)
                    || logs[i].topics[0] != ProceedsVault.ProceedsSkipped.selector
            ) {
                continue;
            }
            (, ProceedsVault.SkipReason r) = abi.decode(logs[i].data, (uint256, ProceedsVault.SkipReason));
            if (r == reason) return;
        }
        fail();
    }

    // ---------------------------------------------------------------- full loops

    function test_DirectTokenPaymentIsForwardedMinusKeep() public {
        vm.recordLogs();
        vm.prank(buyer);
        usd.transfer(address(vault), 25e6);
        assertEq(_relay(), 1);

        assertEq(usd.balanceOf(main), 24e6);
        assertEq(usd.balanceOf(address(vault)), 1e6);
    }

    function test_MarketplaceTokenSaleForwardedOnceDespiteTwoEvents() public {
        vm.prank(seller);
        uint256 id = market.list(address(vault), address(usd), 40e6);

        vm.recordLogs();
        vm.prank(buyer);
        market.buy(id);
        // Transfer route and Sale route both fire for the same tx; the vault dedupes.
        assertEq(_relay(), 2);
        _assertSkipped(ProceedsVault.SkipReason.AlreadyProcessed);

        assertEq(usd.balanceOf(main), 39e6);
        assertEq(usd.balanceOf(address(vault)), 1e6);
    }

    function test_MarketplaceNativeSaleKeepsGasBuffer() public {
        vm.prank(seller);
        uint256 id = market.list(address(vault), address(0), 0.01 ether);

        vm.recordLogs();
        vm.prank(buyer);
        market.buy{value: 0.01 ether}(id);
        assertEq(_relay(), 1);

        assertEq(main.balance, 0.01 ether);
        assertEq(address(vault).balance, GAS_BUFFER);
    }

    function test_NativeForwardNeverDipsIntoGasBuffer() public {
        vm.deal(address(vault), 0); // buffer drained by fees
        vm.prank(seller);
        uint256 id = market.list(address(vault), address(0), 0.0005 ether);

        vm.recordLogs();
        vm.prank(buyer);
        market.buy{value: 0.0005 ether}(id);
        _relay();

        assertEq(main.balance, 0);
        assertEq(address(vault).balance, 0.0005 ether);
    }

    function test_BelowMinimumIsSkipped() public {
        vm.recordLogs();
        vm.prank(buyer);
        usd.transfer(address(vault), 2e6);
        assertEq(_relay(), 1);
        _assertSkipped(ProceedsVault.SkipReason.BelowMinimum);
        assertEq(usd.balanceOf(main), 0);
        assertEq(usd.balanceOf(address(vault)), 2e6);
    }

    function test_NotAllowlistedTokenStays() public {
        MockUSD other = new MockUSD();
        other.mint(buyer, 100e6);
        rc.watchToken(block.chainid, address(other), address(vault));

        vm.recordLogs();
        vm.prank(buyer);
        other.transfer(address(vault), 50e6);
        assertEq(_relay(), 1);
        _assertSkipped(ProceedsVault.SkipReason.TokenNotAllowed);
        assertEq(other.balanceOf(main), 0);
        assertEq(other.balanceOf(address(vault)), 50e6);
    }

    function test_PausedVaultHoldsFunds() public {
        vault.setPaused(true);
        vm.recordLogs();
        vm.prank(buyer);
        usd.transfer(address(vault), 25e6);
        _relay();
        _assertSkipped(ProceedsVault.SkipReason.Paused);
        assertEq(usd.balanceOf(main), 0);
    }

    function test_MainWalletChangeTakesEffect() public {
        address newMain = makeAddr("newMain");
        vault.setMainWallet(newMain);
        vm.recordLogs();
        vm.prank(buyer);
        usd.transfer(address(vault), 25e6);
        _relay();
        assertEq(usd.balanceOf(newMain), 24e6);
    }

    // ---------------------------------------------------------------- reactive side

    function test_ReactIgnoresUnregisteredVault() public {
        address stranger = makeAddr("stranger");
        IReactive.LogRecord memory r;
        r.chainId = block.chainid;
        r.contractAddress = address(usd);
        r.topic0 = rc.TRANSFER_TOPIC0();
        r.topic2 = uint256(uint160(stranger));
        r.opCode = 3;
        r.data = abi.encode(uint256(100e6));
        vm.prank(SYSTEM_ADDR);
        rc.react(r);
        assertEq(sys.callbackCount(), 0);
    }

    function test_ReactIgnoresErc721Transfer() public {
        IReactive.LogRecord memory r;
        r.chainId = block.chainid;
        r.topic0 = rc.TRANSFER_TOPIC0();
        r.topic2 = uint256(uint160(address(vault)));
        r.topic3 = 7;
        r.opCode = 4; // ERC721 has tokenId indexed
        vm.prank(SYSTEM_ADDR);
        rc.react(r);
        assertEq(sys.callbackCount(), 0);
    }

    function test_ReactOnlySystem() public {
        IReactive.LogRecord memory r;
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM_ADDR)
        );
        rc.react(r);
    }

    function test_WatchSubscribesWithVaultAsTopic2() public view {
        (uint256 c, address s, uint256 t0,, uint256 t2,, bool active) = sys.subs(0);
        assertEq(c, block.chainid);
        assertEq(s, address(usd));
        assertEq(t0, rc.TRANSFER_TOPIC0());
        assertEq(t2, uint256(uint160(address(vault))));
        assertTrue(active);
        assertTrue(rc.isVault(block.chainid, address(vault)));
    }

    function test_UnwatchStopsRoute() public {
        rc.unwatchToken(block.chainid, address(usd), address(vault));
        rc.unwatchMarketplace(block.chainid, address(market), address(vault));
        assertFalse(rc.isVault(block.chainid, address(vault)));
        (,,,,,, bool active) = sys.subs(0);
        assertFalse(active);
    }

    function test_OnlyOwnerConfiguresReactive() public {
        vm.prank(buyer);
        vm.expectRevert(ProceedsReactive.NotOwner.selector);
        rc.watchToken(1, address(usd), address(vault));
    }

    function test_SaleTopicMatchesMarketplaceEvent() public view {
        assertEq(bytes32(rc.SALE_TOPIC0()), MockMarketplace.Sale.selector);
        assertEq(bytes32(rc.TRANSFER_TOPIC0()), keccak256("Transfer(address,address,uint256)"));
    }

    // ---------------------------------------------------------------- vault auth & owner

    function test_CallbackRejectsDirectCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy))
        );
        vault.onProceeds(address(rc), block.chainid, address(usd), 1, 1);
    }

    function test_CallbackRejectsOtherReactiveContract() public {
        bytes memory payload =
            abi.encodeCall(ProceedsVault.onProceeds, (address(0), block.chainid, address(usd), 1, 1));
        (bool ok, bytes memory ret) = proxy.deliver(address(vault), payload, buyer);
        assertFalse(ok);
        assertEq(
            ret, abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, buyer, address(rc))
        );
    }

    function test_ReplayedCallbackIsDeduped() public {
        usd.mint(address(vault), 50e6);
        bytes memory payload =
            abi.encodeCall(ProceedsVault.onProceeds, (address(0), 1, address(usd), 20e6, 0xabc));
        proxy.deliver(address(vault), payload, address(rc));
        proxy.deliver(address(vault), payload, address(rc));
        assertEq(usd.balanceOf(main), 19e6);
    }

    function test_ForwardCappedByActualBalance() public {
        usd.mint(address(vault), 10e6);
        bytes memory payload =
            abi.encodeCall(ProceedsVault.onProceeds, (address(0), 1, address(usd), 1_000e6, 0x1));
        proxy.deliver(address(vault), payload, address(rc));
        assertEq(usd.balanceOf(main), 9e6); // 10 available - 1 keep, not the inflated 1000 reported
    }

    function test_OwnerOnlyConfigAndSweep() public {
        vm.startPrank(buyer);
        vm.expectRevert(ProceedsVault.NotOwner.selector);
        vault.setMainWallet(buyer);
        vm.expectRevert(ProceedsVault.NotOwner.selector);
        vault.sweep(address(usd), buyer, 1);
        vm.stopPrank();

        usd.mint(address(vault), 3e6);
        vault.sweep(address(usd), main, 3e6);
        assertEq(usd.balanceOf(main), 3e6);
    }

    function testFuzz_QuoteNeverExceedsReportedOrBalance(uint96 reported, uint96 balance, uint64 keep)
        public
    {
        vault.setTokenRule(address(usd), true, 0, keep);
        usd.mint(address(vault), balance);
        (uint256 send, uint256 kept) = vault.quoteForward(address(usd), reported);
        assertLe(send, reported);
        assertLe(send + kept, uint256(balance) + 0);
        if (send > 0) assertEq(kept, keep);
    }
}
