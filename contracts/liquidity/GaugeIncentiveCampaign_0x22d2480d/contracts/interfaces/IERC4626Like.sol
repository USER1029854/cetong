// IERC4626Like.sol
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC4626Like is IERC20 {
    function asset() external view returns (address);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 sharesBurned);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assetsOut);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);
    // (optional) preview functions if you need them
}
