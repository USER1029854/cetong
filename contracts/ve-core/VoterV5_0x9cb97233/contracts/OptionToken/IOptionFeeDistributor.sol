// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

interface IOptionFeeDistributor {
    struct FeeReceiver {
        address receiver;
        uint256 feeShare;
    }

    function floorPrice() external view returns (uint256);
    function feeReceivers(uint256 index) external view returns (address receiver, uint256 feeShare);
    function permissionsRegistry() external view returns (address);
    function floorGuardian() external view returns (address);

    function setFeeReceiver(address _feeReceiver, uint256 _feeShare, uint256 _index) external;
    function setFloorPrice(uint256 _floorPrice) external;
    function setFloorGuardian(address _floorGuardian) external;

    function distribute(address token, uint256 payoutAmount, uint256 amount) external;
}
