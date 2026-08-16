// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IOption is IAccessControl {
    function paymentToken() external view returns (IERC20);

    function getPaymentAmount(uint256 _amount, bytes calldata _data) external view returns (uint256);

    function exercise(uint256 _amount, address sender, bytes calldata _data) external returns (uint256);
}