// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

/// @notice Stand-in for the Reactive system contract (etched at 0x8888...8888 in tests).
///         Records subscriptions and callback requests instead of acting on them.
contract MockSystem {
    struct Sub {
        uint256 chainId;
        address source;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
        bool active;
    }

    Sub[] public subs;
    ISystemContract.CallbackConfiguration_V_1_0[] internal _callbacks;

    function subscribe(uint256 c, address s, uint256 t0, uint256 t1, uint256 t2, uint256 t3) external {
        subs.push(Sub(c, s, t0, t1, t2, t3, true));
    }

    function unsubscribe(uint256 c, address s, uint256 t0, uint256 t1, uint256 t2, uint256 t3) external {
        for (uint256 i; i < subs.length; ++i) {
            Sub storage x = subs[i];
            if (
                x.chainId == c && x.source == s && x.topic0 == t0 && x.topic1 == t1 && x.topic2 == t2
                    && x.topic3 == t3
            ) {
                x.active = false;
            }
        }
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory cfg) external {
        _callbacks.push(cfg);
    }

    function subCount() external view returns (uint256) {
        return subs.length;
    }

    function callbackCount() external view returns (uint256) {
        return _callbacks.length;
    }

    function callbackAt(uint256 i)
        external
        view
        returns (ISystemContract.CallbackConfiguration_V_1_0 memory)
    {
        return _callbacks[i];
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}
}

/// @notice Stand-in for a destination-chain callback proxy: overwrites the first argument with the
///         requesting reactive contract (as the real network does) and calls the recipient.
contract MockCallbackProxy {
    uint256 public debtOf;

    function deliver(address recipient, bytes memory payload, address reactive)
        external
        returns (bool ok, bytes memory ret)
    {
        assembly {
            // payload layout: [len][selector(4)][arg0(32)]...; arg0 starts at payload + 32 + 4
            mstore(add(payload, 36), reactive)
        }
        (ok, ret) = recipient.call(payload);
    }

    function setDebt(uint256 d) external {
        debtOf = d;
    }

    function debt(address) external view returns (uint256) {
        return debtOf;
    }

    receive() external payable {}
}
