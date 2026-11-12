// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";

/// @title ProceedsVault
/// @notice Receives sale proceeds / payments and forwards them to the owner's main wallet when the
///         Reactive Network tells it (via a callback) that proceeds just landed.
/// @dev Callback contract. Only the chain's Reactive callback proxy may call `onProceeds`, and only on
///      behalf of the single reactive contract fixed at deployment (`_CALLBACK_SENDER`).
///      Every decision emits an event so the whole pipeline can be audited from logs alone.
contract ProceedsVault is AbstractCallback {
    /// @dev Token address used for the chain's native currency (ETH on Sepolia).
    address public constant NATIVE = address(0);

    /// @notice Per-token forwarding rule.
    /// @param allowed   Token is on the allowlist; anything else stays in the vault.
    /// @param minAmount Reported proceeds below this are ignored (dust / spam protection).
    /// @param keep      Amount retained in the vault from every forward (e.g. a keep-for-gas cut).
    struct TokenRule {
        bool allowed;
        uint128 minAmount;
        uint128 keep;
    }

    enum SkipReason {
        Paused,
        TokenNotAllowed,
        BelowMinimum,
        AlreadyProcessed,
        NothingToForward,
        TransferFailed
    }

    address public owner;
    address public mainWallet;
    bool public paused;
    /// @notice Native balance that is never forwarded, so the vault can keep paying callback fees.
    uint256 public nativeGasBuffer;

    mapping(address token => TokenRule) public rules;
    /// @notice keccak256(originChainId, originTxHash, token) => already handled.
    mapping(bytes32 key => bool) public processed;

    event CallbackReceived(
        uint256 indexed originChainId, uint256 indexed originTxHash, address indexed token, uint256 reported
    );
    event ProceedsForwarded(
        address indexed token, address indexed to, uint256 amount, uint256 kept, uint256 indexed originTxHash
    );
    event ProceedsSkipped(
        address indexed token, uint256 reported, SkipReason reason, uint256 indexed originTxHash
    );
    event NativeReceived(address indexed from, uint256 amount);
    event TokenRuleSet(address indexed token, bool allowed, uint128 minAmount, uint128 keep);
    event MainWalletSet(address indexed previous, address indexed current);
    event GasBufferSet(uint256 previous, uint256 current);
    event PausedSet(bool paused);
    event OwnershipTransferred(address indexed previous, address indexed current);
    event ManualSweep(address indexed token, address indexed to, uint256 amount);

    error NotOwner();
    error ZeroAddress();
    error SweepFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param callbackProxy_  Reactive callback proxy of this chain (see Origins & Destinations docs).
    /// @param reactive_       The ProceedsReactive contract on Reactive Lasna allowed to trigger forwards.
    /// @param mainWallet_     Where proceeds go.
    /// @param nativeGasBuffer_ Native balance kept back to fund callback fees.
    constructor(IPayable callbackProxy_, address reactive_, address mainWallet_, uint256 nativeGasBuffer_)
        payable
        AbstractCallback(callbackProxy_, reactive_)
    {
        if (mainWallet_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        mainWallet = mainWallet_;
        nativeGasBuffer = nativeGasBuffer_;
        emit OwnershipTransferred(address(0), msg.sender);
        emit MainWalletSet(address(0), mainWallet_);
        emit GasBufferSet(0, nativeGasBuffer_);
    }

    // ------------------------------------------------------------------ callback

    /// @notice Called by the Reactive callback proxy after proceeds were detected on-chain.
    /// @param reactive_      Overwritten by the network with the requesting reactive contract.
    /// @param originChainId_ Chain where the payment/sale event was observed.
    /// @param token_         Token of the proceeds (`NATIVE` for the chain currency).
    /// @param amount_        Amount reported by the origin event.
    /// @param originTxHash_  Origin transaction hash (dedupe key + audit trail).
    /// @dev Never reverts on business rules: a skip is an event, so the callback is not wasted as a failure.
    function onProceeds(
        address reactive_,
        uint256 originChainId_,
        address token_,
        uint256 amount_,
        uint256 originTxHash_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        emit CallbackReceived(originChainId_, originTxHash_, token_, amount_);

        bytes32 key = keccak256(abi.encode(originChainId_, originTxHash_, token_));
        if (processed[key]) return _skip(token_, amount_, SkipReason.AlreadyProcessed, originTxHash_);
        processed[key] = true;

        if (paused) return _skip(token_, amount_, SkipReason.Paused, originTxHash_);

        TokenRule memory rule = rules[token_];
        if (!rule.allowed) return _skip(token_, amount_, SkipReason.TokenNotAllowed, originTxHash_);
        if (amount_ < rule.minAmount) return _skip(token_, amount_, SkipReason.BelowMinimum, originTxHash_);

        (uint256 send, uint256 kept) = quoteForward(token_, amount_);
        if (send == 0) return _skip(token_, amount_, SkipReason.NothingToForward, originTxHash_);

        if (!_transferOut(token_, mainWallet, send)) {
            return _skip(token_, amount_, SkipReason.TransferFailed, originTxHash_);
        }
        emit ProceedsForwarded(token_, mainWallet, send, kept, originTxHash_);
    }

    // ------------------------------------------------------------------ views

    /// @notice How much of `reported_` would be forwarded right now, and how much would be kept.
    /// @dev Never forwards more than the vault can spare: native balance above the gas buffer,
    ///      or the token balance. The per-token `keep` is subtracted from what is sent.
    function quoteForward(address token_, uint256 reported_)
        public
        view
        returns (uint256 send, uint256 kept)
    {
        uint256 available = spendable(token_);
        uint256 gross = reported_ < available ? reported_ : available;
        uint256 keep = rules[token_].keep;
        if (gross <= keep) return (0, gross);
        return (gross - keep, keep);
    }

    /// @notice Balance of `token_` the vault may forward (native excludes the gas buffer).
    function spendable(address token_) public view returns (uint256) {
        if (token_ == NATIVE) {
            uint256 bal = address(this).balance;
            return bal > nativeGasBuffer ? bal - nativeGasBuffer : 0;
        }
        return IERC20(token_).balanceOf(address(this));
    }

    // ------------------------------------------------------------------ owner config

    function setTokenRule(address token_, bool allowed_, uint128 minAmount_, uint128 keep_)
        external
        onlyOwner
    {
        rules[token_] = TokenRule(allowed_, minAmount_, keep_);
        emit TokenRuleSet(token_, allowed_, minAmount_, keep_);
    }

    function setMainWallet(address mainWallet_) external onlyOwner {
        if (mainWallet_ == address(0)) revert ZeroAddress();
        emit MainWalletSet(mainWallet, mainWallet_);
        mainWallet = mainWallet_;
    }

    function setNativeGasBuffer(uint256 buffer_) external onlyOwner {
        emit GasBufferSet(nativeGasBuffer, buffer_);
        nativeGasBuffer = buffer_;
    }

    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedSet(paused_);
    }

    function transferOwnership(address newOwner_) external onlyOwner {
        if (newOwner_ == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner_);
        owner = newOwner_;
    }

    /// @notice Escape hatch: move any balance out by hand (ignores rules and the gas buffer).
    function sweep(address token_, address to_, uint256 amount_) external onlyOwner {
        if (to_ == address(0)) revert ZeroAddress();
        if (!_transferOut(token_, to_, amount_)) revert SweepFailed();
        emit ManualSweep(token_, to_, amount_);
    }

    /// @notice Settle callback-proxy debt from the vault's native balance. Open to anyone, so a third
    ///         party can revive a stalled vault by sending ETH and calling this.
    function coverDebt() external {
        _coverDebt();
    }

    receive() external payable override {
        emit NativeReceived(msg.sender, msg.value);
    }

    // ------------------------------------------------------------------ internals

    function _skip(address token_, uint256 amount_, SkipReason reason_, uint256 originTxHash_) private {
        emit ProceedsSkipped(token_, amount_, reason_, originTxHash_);
    }

    /// @dev Returns false instead of reverting so a bad token cannot brick the callback.
    function _transferOut(address token_, address to_, uint256 amount_) private returns (bool) {
        if (token_ == NATIVE) {
            (bool ok,) = payable(to_).call{value: amount_}("");
            return ok;
        }
        (bool success, bytes memory ret) = token_.call(abi.encodeCall(IERC20.transfer, (to_, amount_)));
        return success && (ret.length == 0 || abi.decode(ret, (bool)));
    }
}
