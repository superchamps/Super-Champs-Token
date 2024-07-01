// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IVestingEscrow.sol";
import "../Utils/SCPermissionedAccess.sol";
import "../Utils/ABDKMath64x64.sol";
import "../../interfaces/IPermissionsManager.sol";

/// @title An exponential decay-rate emissions vesting contract.
/// @author Chance Santana-Wees (Coel.eth/Coelacanth)
/// @dev Solidity implementation of https://github.com/LlamaPay/yearn-vesting-escrow contract. Modified to emit at an exponentially decaying rate with no finite vesting period.
contract ExponentialVestingEscrow is IVestingEscrow, SCPermissionedAccess {
    ///@notice Emitted when the contract is funded with emissions tokens
    event Fund(address recipient, uint256 amount);
    
    ///@notice Emitted when emissions tokens are claimed by the recipient
    event Claim(address recipient, uint256 claimed);

    ///@notice Emitted when the recipient address is changed
    event RecipientChanged(address recipient);

    ///@notice The address of the beneficiary of the token emissions
    address public recipient;

    ///@notice The emissions token contract
    IERC20 public token; 

    ///@notice The time at which the emissions contract is set to have started emitting tokens
    uint256 public start_time;

    ///@notice The rate at which tokens are emitted per second. 
    ///@dev A fixed point value represented using the format from ABDKMath64x64
    int128 public rate_per_second;

    ///@notice The total quantity of emissions tokens locked at the time of initialization
    uint256 public total_locked;

    ///@notice The total quantity of emissions tokens that have been withdrawn
    uint256 public total_claimed;

    ///@notice Toggle that indicates if the emissions contract has been initialized
    bool public initialized;

    ///@notice Toggle that indicates if the token contract is in the process of executing a transaction that could be vulnerable to a re-entrancy attack
    bool _reentrancy_locked;

    using ABDKMath64x64 for int128;

    ///@notice A function modifier that prevents re-entrancy attacks during sensitive operations
    modifier nonreentrant {
        require(!_reentrancy_locked);
        _reentrancy_locked = true;
        _;
        _reentrancy_locked = false; 
    }

    ///@param permissions_ The address of the permissions registry. Must conform to IPermissionsManager.
    constructor(address permissions_) SCPermissionedAccess(permissions_){ }
    
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

    /// @notice Transfer tokens that have been sent to this contract by mistake.
    /// @dev Only callable by address with Global Admin permissions. Cannot be called to withdraw emissions tokens.
    /// @param tokenAddress_ The address of the token to recover
    /// @param tokenAmount_ The amount of the token to recover
    function recoverERC20(address tokenAddress_, uint256 tokenAmount_) external isGlobalAdmin {
        require(tokenAddress_ != address(token), "Cannot withdraw the emissions token");
        IERC20(tokenAddress_).transfer(msg.sender, tokenAmount_);
    }
}
