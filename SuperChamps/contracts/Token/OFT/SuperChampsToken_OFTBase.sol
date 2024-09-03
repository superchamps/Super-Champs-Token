// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SuperChampsToken_OFT } from "./SuperChampsToken_OFT.sol";

contract SuperChampsToken_OFTBase is 
        OFTAdapter,
        SuperChampsToken_OFT {
    constructor() 
        OFTAdapter( BASE_CHAMP_TOKEN, 
                    LZ_ENDPOINT_BASE, 
                    BASE_OWNER)
        Ownable(    BASE_OWNER) 
    { }

    function initSetup() public onlyOwner {
        setDelegate(INIT_DELEGATE);
        setPeer(BASE_EID, bytes32(uint256(uint160(address(this)))));
    }
}