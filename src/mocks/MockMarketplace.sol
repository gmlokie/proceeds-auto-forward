// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MockMarketplace
/// @notice Minimal fixed-price marketplace. A seller lists an item with a payout address (`payee`);
///         a buyer pays in an ERC20 or the native currency and the money goes straight to the payee.
///         Every sale emits `Sale`, the event ProceedsReactive watches.
contract MockMarketplace {
    using SafeERC20 for IERC20;

    struct Listing {
        address seller;
        address payee;
        address paymentToken; // address(0) = native currency
        uint256 price;
        bool active;
    }

    uint256 public nextListingId = 1;
    mapping(uint256 id => Listing) public listings;

    event Listed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed payee,
        address paymentToken,
        uint256 price
    );
    event Cancelled(uint256 indexed listingId);
    event Sale(
        uint256 indexed listingId,
        address indexed payee,
        address indexed paymentToken,
        uint256 price,
        address seller,
        address buyer
    );

    error NotSeller();
    error NotActive();
    error WrongValue();
    error ZeroAddress();
    error NativePayoutFailed();

    function list(address payee_, address paymentToken_, uint256 price_) external returns (uint256 id) {
        if (payee_ == address(0)) revert ZeroAddress();
        id = nextListingId++;
        listings[id] = Listing(msg.sender, payee_, paymentToken_, price_, true);
        emit Listed(id, msg.sender, payee_, paymentToken_, price_);
    }

    function cancel(uint256 id_) external {
        Listing storage l = listings[id_];
        if (l.seller != msg.sender) revert NotSeller();
        if (!l.active) revert NotActive();
        l.active = false;
        emit Cancelled(id_);
    }

    function buy(uint256 id_) external payable {
        Listing storage l = listings[id_];
        if (!l.active) revert NotActive();
        l.active = false;

        if (l.paymentToken == address(0)) {
            if (msg.value != l.price) revert WrongValue();
            (bool ok,) = payable(l.payee).call{value: msg.value}("");
            if (!ok) revert NativePayoutFailed();
        } else {
            if (msg.value != 0) revert WrongValue();
            IERC20(l.paymentToken).safeTransferFrom(msg.sender, l.payee, l.price);
        }
        emit Sale(id_, l.payee, l.paymentToken, l.price, l.seller, msg.sender);
    }
}
