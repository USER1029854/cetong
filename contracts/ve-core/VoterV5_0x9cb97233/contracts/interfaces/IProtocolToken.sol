// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IProtocolToken is IERC20, IERC20Permit {
    function mint(address, uint) external;
    function acceptOwnership() external;
    function burn(uint) external;
    function burnFrom(address, uint) external;
}