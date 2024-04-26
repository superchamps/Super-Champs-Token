// SPDX-License-Identifier: None
// Joyride Games 2024

pragma solidity ^0.8.24;

import "../../interfaces/IVestingEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Utils/ABDKMath64x64.sol";
import "../../interfaces/IPermissionsManager.sol";

/// @title An exponential decay-rate emissions vesting contract.
/// @author Chance Santana-Wees
/// @dev Solidity implementation of https://github.com/LlamaPay/yearn-vesting-escrow contract. Modified to emit at an exponentially decaying rate with no finite vesting period.
contract ExponentialVestingEscrow is IVestingEscrow {
    event Fund(address recipient, uint256 amount);
    event Claim(address recipient, uint256 claimed);
    event RecipientChanged(address recipient);

    IPermissionsManager immutable private _permissions;
    address private _creator;
    address public recipient;
    IERC20 public token; 
    uint256 public start_time;
    int128 public rate_per_second;
    uint256 public total_locked;
    uint256 public total_claimed;
    bool public initialized;

    bool _reentrancy_locked;

    uint256 private _ts;

    using ABDKMath64x64 for int128;

    modifier nonreentrant {
        require(!_reentrancy_locked);
        _reentrancy_locked = true;
        _;
        _reentrancy_locked = false; 
    }

    modifier isGlobalAdmin() {
        require(_permissions.hasRole(IPermissionsManager.Role.GLOBAL_ADMIN, msg.sender));
        _;
    }

    constructor(
        address permissions_
    ) {
        _creator = msg.sender;
        _permissions = IPermissionsManager(permissions_);
    }
    
    /**
    * @notice Initialize the emissions contract.
    * @dev The rate_per_second is calculated as (1 - rate_per_second_numerator_/rate_per_second_denominator_) and is utilized in the following emissions function:
    * {vested_quantity} = {amount_} - ({rate_per_second}^{elapsed_seconds})*{amount_}
    * @param token_ Address of the ERC20 token being distributed
    * @param recipient_ Address to vest tokens for
    * @param amount_ Amount of tokens being vested for `recipient`
    * @param start_time_ Epoch time at which token distribution starts
    * @param rate_per_second_numerator_ The top of the numerator emissions rate per second
    * @param rate_per_second_denominator_ The bottom of the denominator emissions rate per second
    **/
    function initialize(
        address,
        address token_,
        address recipient_,
        uint256 amount_,
        uint256 start_time_,
        uint256 rate_per_second_numerator_,
        uint256 rate_per_second_denominator_
    ) external nonreentrant returns(bool)
    {
        require(!initialized);

        initialized = true;
        token = IERC20(token_);
        start_time = start_time_;
        rate_per_second = ABDKMath64x64.sub(
            ABDKMath64x64.fromUInt(1), 
            ABDKMath64x64.divi(int256(rate_per_second_numerator_), int256(rate_per_second_denominator_)));

        bool transfer_success_ = token.transferFrom(msg.sender, address(this), amount_);
        require(transfer_success_, "TRANSFER FAILED");

        recipient = recipient_;
        total_locked = amount_;
        emit Fund(recipient, amount_);

        return true;
    }

    function _timeStamp() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
    * @notice Read the total amount vested at a given timestamp.
    * @dev The rate_per_second is calculated as (1 - rate_per_second_numerator_/rate_per_second_denominator_). 
    * The function which calculates the vested quantity of tokens is: {amount_} - ({rate_per_second}^{elapsed_seconds})*{amount_}
    * @param time_ The timestamp that the total amount vested will be calculated for.
    **/
    function _totalVestedAt(
        uint256 time_
    ) internal view returns (uint256) 
    {
        if(time_ < start_time) { return 0; }

        uint256 _seconds = time_ - start_time;
        int128 _emitted_ratio = ABDKMath64x64.pow(rate_per_second, _seconds);
        uint256 _total_remaining = ABDKMath64x64.mulu(_emitted_ratio, total_locked);

        require(_total_remaining < total_locked);
        return total_locked - _total_remaining;
    }

    /**
    * @notice Read the total amount of tokens that are claimable but have NOT been claimed from the emissions contract.
    * @dev Calculated by subtracting the total amount claimed from the total amount vested at the current timestamp. 
    **/
    function unclaimed() public view returns(uint256)
    {
        return uint256(_totalVestedAt(_timeStamp()) - total_claimed);
    }

    /**
    * @notice Read the total amount of tokens that are still locked in the emissions contract.
    * @dev Calculated by subtracting the total amount vested at the current timestamp from the total amount locked.
    **/
    function locked() public view returns(uint256)
    {
        return total_locked - _totalVestedAt(_timeStamp());
    }

    /**
    * @notice Allows a global admin to change the emissions beneficiary.
    * @dev Changes the beneficiary to the address newRecipient_, then emit an event recording this change.
    * @param newRecipient_ The new beneficiary address.
    **/
    function changeRecipient(
        address newRecipient_
    ) public isGlobalAdmin {
        recipient = newRecipient_;
        emit RecipientChanged(recipient);
    }

    /**
    * @notice Transfer the current unlocked unclaimed tokens to the beneficiary address.
    * @dev Calculates maximum claimable_ token balance with unclaimed(), increments total_claimed, transfers claimable_ tokens to the beneficiary. 
    * @param beneficiary_ The requested beneficiary address. MUST be recipient.
    * @param amount_ The max quantity of tokens to be transferred. If 0, all unclaimed tokens are transferred.
    **/
    function claim(
        address beneficiary_,
        uint256 amount_
    ) external nonreentrant {
        require(beneficiary_ == recipient);

        uint256 claimable_ = unclaimed();
        if(amount_ != 0 && claimable_ > amount_) {claimable_ = amount_;}
        total_claimed += claimable_;

        bool transfer_success_ = token.transfer(beneficiary_, claimable_);
        require(transfer_success_);
        
        emit Claim(beneficiary_, claimable_);
    }

    /**
    * @notice Transfer tokens other than the emissions token to the recipient.
    * @dev Collects tokens that have been transferred to the emissions contract by mistake to the recipient address. 
    **/
    function collect_dust(
        address token_
    ) public nonreentrant isGlobalAdmin
    {
        require(token != IERC20(token_));
        bool transfer_success_ = IERC20(token_).transfer(recipient, IERC20(token_).balanceOf(address(this)));
        require(transfer_success_);
    }
}