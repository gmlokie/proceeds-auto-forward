// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";

/// @title ProceedsReactive
/// @notice Lives on Reactive Network (Lasna testnet). Watches origin chains for money arriving at a
///         registered ProceedsVault and asks the network to call `ProceedsVault.onProceeds` on the
///         vault's chain, so proceeds are forwarded to the owner's main wallet with no bot or keeper.
/// @dev Two kinds of route are supported, each one an event subscription:
///      - Token route: ERC20 `Transfer(from, to = vault, value)` on a given token.
///      - Marketplace route: `Sale(listingId, payee = vault, paymentToken, price, seller, buyer)` on a
///        marketplace, covering both ERC20 and native-currency sales.
///      The vault lives on the same chain the event happened on (that is where the money is), and one
///      reactive contract can serve vaults on every supported chain at once.
contract ProceedsReactive is AbstractReactive {
    /// @dev keccak256("Transfer(address,address,uint256)")
    uint256 public constant TRANSFER_TOPIC0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    /// @dev keccak256("Sale(uint256,address,address,uint256,address,address)")
    uint256 public constant SALE_TOPIC0 =
        uint256(keccak256("Sale(uint256,address,address,uint256,address,address)"));

    enum RouteKind {
        Token,
        Marketplace
    }

    address public owner;
    uint64 public callbackGasLimit;

    /// @notice keccak256(chainId, vault) => vault is registered (guards against spoofed payees).
    mapping(bytes32 key => uint256 activeRoutes) public vaultRoutes;

    event RouteWatched(
        RouteKind indexed kind, uint256 indexed chainId, address indexed source, address vault
    );
    event RouteUnwatched(
        RouteKind indexed kind, uint256 indexed chainId, address indexed source, address vault
    );
    event ProceedsDetected(
        uint256 indexed chainId,
        address indexed vault,
        address indexed token,
        uint256 amount,
        RouteKind kind,
        uint256 originTxHash
    );
    event ForwardRequested(
        uint256 indexed chainId, address indexed vault, address indexed token, uint256 amount
    );
    event CallbackGasLimitSet(uint64 gasLimit);
    event OwnershipTransferred(address indexed previous, address indexed current);

    error NotOwner();
    error ZeroAddress();
    error GasLimitTooLow();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(uint64 callbackGasLimit_) payable {
        if (callbackGasLimit_ < 100_000) revert GasLimitTooLow();
        owner = msg.sender;
        callbackGasLimit = callbackGasLimit_;
        emit OwnershipTransferred(address(0), msg.sender);
        emit CallbackGasLimitSet(callbackGasLimit_);
    }

    // ------------------------------------------------------------------ routes

    /// @notice Forward every `token` transfer into `vault` on `chainId`.
    function watchToken(uint256 chainId_, address token_, address vault_) external onlyOwner {
        _route(RouteKind.Token, chainId_, token_, vault_, true);
    }

    /// @notice Forward every `marketplace` sale whose payee is `vault` on `chainId`.
    function watchMarketplace(uint256 chainId_, address marketplace_, address vault_) external onlyOwner {
        _route(RouteKind.Marketplace, chainId_, marketplace_, vault_, true);
    }

    function unwatchToken(uint256 chainId_, address token_, address vault_) external onlyOwner {
        _route(RouteKind.Token, chainId_, token_, vault_, false);
    }

    function unwatchMarketplace(uint256 chainId_, address marketplace_, address vault_) external onlyOwner {
        _route(RouteKind.Marketplace, chainId_, marketplace_, vault_, false);
    }

    function isVault(uint256 chainId_, address vault_) public view returns (bool) {
        return vaultRoutes[_vaultKey(chainId_, vault_)] > 0;
    }

    // ------------------------------------------------------------------ react

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        address vault;
        address token;
        uint256 amount;
        RouteKind kind;

        if (log_.topic0 == TRANSFER_TOPIC0 && log_.opCode == 3) {
            // ERC20 Transfer(from, to, value): `to` is topic2, value is the only data word.
            // (ERC721 Transfer has 4 topics, so opCode filters it out.)
            vault = address(uint160(log_.topic2));
            token = log_.contractAddress;
            amount = abi.decode(log_.data, (uint256));
            kind = RouteKind.Token;
        } else if (log_.topic0 == SALE_TOPIC0 && log_.opCode == 4) {
            // Sale(listingId, payee, paymentToken, price, seller, buyer)
            vault = address(uint160(log_.topic2));
            token = address(uint160(log_.topic3));
            (amount,,) = abi.decode(log_.data, (uint256, address, address));
            kind = RouteKind.Marketplace;
        } else {
            return; // not ours: fall through cheaply, never revert as a filter
        }

        if (amount == 0 || !isVault(log_.chainId, vault)) return;

        emit ProceedsDetected(log_.chainId, vault, token, amount, kind, log_.txHash);
        emit ForwardRequested(log_.chainId, vault, token, amount);

        bytes memory payload = abi.encodeWithSignature(
            "onProceeds(address,uint256,address,uint256,uint256)",
            address(0), // replaced by the network with this contract's address
            log_.chainId,
            token,
            amount,
            log_.txHash
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: log_.chainId, recipient: vault, gasLimit: callbackGasLimit, payload: payload
            })
        );
    }

    // ------------------------------------------------------------------ owner

    function setCallbackGasLimit(uint64 gasLimit_) external onlyOwner {
        if (gasLimit_ < 100_000) revert GasLimitTooLow();
        callbackGasLimit = gasLimit_;
        emit CallbackGasLimitSet(gasLimit_);
    }

    function transferOwnership(address newOwner_) external onlyOwner {
        if (newOwner_ == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner_);
        owner = newOwner_;
    }

    /// @notice Settle system-contract debt from this contract's balance (anyone may revive it).
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice Withdraw spare lREACT/REACT.
    function withdraw(address payable to_, uint256 amount_) external onlyOwner {
        if (to_ == address(0)) revert ZeroAddress();
        _pay(to_, amount_);
    }

    // ------------------------------------------------------------------ internals

    function _route(RouteKind kind_, uint256 chainId_, address source_, address vault_, bool on_) private {
        if (source_ == address(0) || vault_ == address(0)) revert ZeroAddress();
        uint256 topic0 = kind_ == RouteKind.Token ? TRANSFER_TOPIC0 : SALE_TOPIC0;
        bytes32 key = _vaultKey(chainId_, vault_);
        if (on_) {
            vaultRoutes[key] += 1;
            emit RouteWatched(kind_, chainId_, source_, vault_);
            SYSTEM.subscribe(
                chainId_, source_, topic0, REACTIVE_IGNORE, uint256(uint160(vault_)), REACTIVE_IGNORE
            );
        } else {
            if (vaultRoutes[key] > 0) vaultRoutes[key] -= 1;
            emit RouteUnwatched(kind_, chainId_, source_, vault_);
            SYSTEM.unsubscribe(
                chainId_, source_, topic0, REACTIVE_IGNORE, uint256(uint160(vault_)), REACTIVE_IGNORE
            );
        }
    }

    function _vaultKey(uint256 chainId_, address vault_) private pure returns (bytes32) {
        return keccak256(abi.encode(chainId_, vault_));
    }
}
