// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IDynamicTwapOracle} from "./DynamicTwapOracle/IDynamicTwapOracle.sol";
import {IOptionFeeDistributor} from "./IOptionFeeDistributor.sol";
import {IPair} from "../interfaces/IPair.sol";
import {IOption} from "./IOption.sol";

interface IOptionTokenV4 is IERC20, IAccessControl {
    function ADMIN_ROLE() external view returns (bytes32);

    function MINTER_ROLE() external view returns (bytes32);

    function PAUSER_ROLE() external view returns (bytes32);

    function paymentToken() external view returns (IERC20);

    function UNDERLYING_TOKEN() external view returns (IERC20);

    function voter() external view returns (address);

    function mint(address _to, uint256 _amount) external;

    function exercise(uint256 _amount, uint256 _maxPaymentAmount, address _recipient) external returns (uint256);

    function exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient,
        uint256 _deadline
    ) external returns (uint256);

    function exerciseVe(
        uint256 _amount,
        address _recipient
    ) external returns (uint256);

    function exerciseExternal(
        IOption _option,
        uint256 _amount,
        uint256 _deadline,
        bytes calldata _data
    ) external returns (uint256);

    function getVotingEscrow() external view returns (address votingEscrow);

    function togglePermissionedMint() external;

    function toggleExternalOption(address option, bool enabled) external;

    function getDiscountedPrice(uint256 _amount) external view returns (uint256);

    function getDiscountedPrice(uint256 _amount, uint256 _discount) external view returns (uint256);

    function getTimeWeightedAveragePrice(uint256 _amount) external view returns (uint256);

    function setPaymentConfiguration(IPair _pair, IDynamicTwapOracle _twapOracle, address _paymentToken) external;

    function setFeeDistributor(IOptionFeeDistributor _feeDistributor) external;

    function setDiscount(uint256 _discount) external;

    function setTwapSeconds(uint32 _twapSeconds) external;

    function getMinPrice(uint256 _amount, uint256 _discount) external view returns (uint256);

    function burn(uint256 _amount) external;

    function unPause() external;

    function pause() external;
} 