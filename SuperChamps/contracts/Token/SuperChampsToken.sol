// SPDX-License-Identifier: None
// Joyride Games 2024

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../../interfaces/IPermissionsManager.sol";

contract SuperChampsToken is ERC20, ERC20Permit {
    IPermissionsManager immutable public permissions;
    uint256 public immutable TOTAL_SUPPLY;

    bool public transfersLocked;

    modifier isAdminOrUnlocked() {
        require(!transfersLocked || 
                permissions.hasRole(IPermissionsManager.Role.ANY, _msgSender()) ||
                permissions.hasRole(IPermissionsManager.Role.ANY, tx.origin));
        _;
    }

    modifier isGlobalAdmin() {
        require(permissions.hasRole(IPermissionsManager.Role.GLOBAL_ADMIN, _msgSender()));
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 total_supply_,
        IPermissionsManager permissions_
    ) 
        ERC20(name_, symbol_) 
        ERC20Permit(name_) 
    {
        TOTAL_SUPPLY = total_supply_;
        permissions = permissions_;
    }

    function tokenGenerationEvent(
        address[] memory mint_recipients_,
        uint256[] memory mint_quantities_)
        public isGlobalAdmin 
    {
        require(totalSupply() == 0, "TOKEN ALREADY GENERATED");
        require(mint_recipients_.length == mint_quantities_.length, "INCORRECT PARAM LENGTHS");
        require(permissions.hasRole(IPermissionsManager.Role.TRANSFER_ADMIN, address(this)), "TOKEN NOT TRANSFER ADMIN");
        
        for(uint256 i = 0; i < mint_recipients_.length; i++) {
            _mint(address(mint_recipients_[i]), mint_quantities_[i]);
        }

        require(totalSupply() == TOTAL_SUPPLY, "INCORRECT SUPPLY");
        transfersLocked = true;
    }

    function transfer(
        address to, 
        uint256 amount
    ) public override isAdminOrUnlocked returns(bool){
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from, 
        address to, 
        uint256 amount
    ) public override isAdminOrUnlocked returns(bool) {
        return super.transferFrom(from, to, amount);
    }

    function unlockTransfers() public isGlobalAdmin{
        transfersLocked = false;
    }
}