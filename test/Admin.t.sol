// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {ProceedsVault} from "../src/destination/ProceedsVault.sol";
import {ProceedsReactive} from "../src/reactive/ProceedsReactive.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";
import {MockSystem, MockCallbackProxy} from "./utils/Mocks.sol";

/// @dev Rejects ETH, to exercise the vault's TransferFailed path.
contract NoEth {
    receive() external payable {
        revert("no");
    }
}

/// @notice Owner/admin surface and the remaining skip paths of both contracts.
contract AdminAndEdgeCasesTest is Test {
    address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;

    MockSystem sys;
    MockCallbackProxy proxy;
    ProceedsReactive rc;
    ProceedsVault vault;
    MockUSD usd;
    address main = makeAddr("main");
    address stranger = makeAddr("stranger");

    function setUp() public {
        vm.etch(SYSTEM_ADDR, address(new MockSystem()).code);
        sys = MockSystem(payable(SYSTEM_ADDR));
        proxy = new MockCallbackProxy();
        rc = new ProceedsReactive{value: 1 ether}(1_000_000);
        vault = new ProceedsVault(IPayable(payable(address(proxy))), address(rc), main, 0.001 ether);
        usd = new MockUSD();
        vault.setTokenRule(address(usd), true, 1e6, 5e6);
        vault.setTokenRule(address(0), true, 1, 0);
    }

    function _deliver(address token, uint256 amount, uint256 txh) internal returns (bool ok) {
        bytes memory p = abi.encodeCall(ProceedsVault.onProceeds, (address(0), block.chainid, token, amount, txh));
        (ok,) = proxy.deliver(address(vault), p, address(rc));
    }

    // ------------------------------------------------------------- reactive admin

    function test_ReactiveConstructorRejectsLowGasLimit() public {
        vm.expectRevert(ProceedsReactive.GasLimitTooLow.selector);
        new ProceedsReactive(99_999);
    }

    function test_SetCallbackGasLimit() public {
        rc.setCallbackGasLimit(2_000_000);
        assertEq(rc.callbackGasLimit(), 2_000_000);
        vm.expectRevert(ProceedsReactive.GasLimitTooLow.selector);
        rc.setCallbackGasLimit(1);
        vm.prank(stranger);
        vm.expectRevert(ProceedsReactive.NotOwner.selector);
        rc.setCallbackGasLimit(2_000_000);
    }

    function test_ReactiveOwnershipTransfer() public {
        vm.expectRevert(ProceedsReactive.ZeroAddress.selector);
        rc.transferOwnership(address(0));
        rc.transferOwnership(stranger);
        assertEq(rc.owner(), stranger);
        vm.expectRevert(ProceedsReactive.NotOwner.selector);
        rc.watchToken(1, address(usd), address(vault));
    }

    function test_ReactiveWithdraw() public {
        address payable to = payable(makeAddr("treasury"));
        rc.withdraw(to, 0.4 ether);
        assertEq(to.balance, 0.4 ether);
        vm.expectRevert(ProceedsReactive.ZeroAddress.selector);
        rc.withdraw(payable(address(0)), 1);
        vm.prank(stranger);
        vm.expectRevert(ProceedsReactive.NotOwner.selector);
        rc.withdraw(to, 1);
    }

    function test_WatchRejectsZeroAddresses() public {
        vm.expectRevert(ProceedsReactive.ZeroAddress.selector);
        rc.watchToken(1, address(0), address(vault));
        vm.expectRevert(ProceedsReactive.ZeroAddress.selector);
        rc.watchMarketplace(1, address(usd), address(0));
    }

    function test_ReactiveCoverDebtIsPublic() public {
        vm.prank(stranger);
        rc.coverDebt(); // no debt on the mock: must simply not revert
    }

    // ------------------------------------------------------------- vault admin + edge paths

    function test_VaultConstructorRejectsZeroMainWallet() public {
        vm.expectRevert(ProceedsVault.ZeroAddress.selector);
        new ProceedsVault(IPayable(payable(address(proxy))), address(rc), address(0), 0);
    }

    function test_VaultOwnershipAndBuffer() public {
        vault.setNativeGasBuffer(0.002 ether);
        assertEq(vault.nativeGasBuffer(), 0.002 ether);
        vm.expectRevert(ProceedsVault.ZeroAddress.selector);
        vault.transferOwnership(address(0));
        vault.transferOwnership(stranger);
        vm.expectRevert(ProceedsVault.NotOwner.selector);
        vault.setPaused(true);
    }

    function test_KeepLargerThanAmountIsNothingToForward() public {
        usd.mint(address(vault), 3e6); // min 1, keep 5: everything stays
        assertTrue(_deliver(address(usd), 3e6, 1));
        assertEq(usd.balanceOf(main), 0);
        assertEq(usd.balanceOf(address(vault)), 3e6);
    }

    function test_FailedNativeTransferIsSkippedNotReverted() public {
        NoEth bad = new NoEth();
        vault.setMainWallet(address(bad));
        vm.deal(address(vault), 0.01 ether);
        assertTrue(_deliver(address(0), 0.005 ether, 2)); // TransferFailed is an event, callback succeeds
        assertEq(address(vault).balance, 0.01 ether);
    }

    function test_SweepNativeAndFailure() public {
        vm.deal(address(vault), 0.01 ether);
        vault.sweep(address(0), main, 0.01 ether);
        assertEq(main.balance, 0.01 ether);
        vm.expectRevert(ProceedsVault.SweepFailed.selector);
        vault.sweep(address(0), main, 1 ether);
        vm.expectRevert(ProceedsVault.ZeroAddress.selector);
        vault.sweep(address(0), address(0), 1);
    }

    function test_VaultReceivesNativeAndCoverDebtIsPublic() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool ok,) = address(vault).call{value: 0.1 ether}("");
        assertTrue(ok);
        assertEq(vault.spendable(address(0)), 0.099 ether);
        vm.prank(stranger);
        vault.coverDebt();
    }
}
