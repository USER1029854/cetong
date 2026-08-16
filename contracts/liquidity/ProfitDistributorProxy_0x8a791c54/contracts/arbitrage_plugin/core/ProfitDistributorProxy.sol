// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IProfitDistributor.sol";

contract ProfitDistributorProxy is IProfitDistributor, Ownable, Initializable {
	using SafeERC20 for IERC20;

	uint256 public constant SHARE_DENOMINATOR = 10_000;

	ProfitShareConfig public defaultConfig;
	mapping(bytes32 => ProfitShareConfig) public configs;
	address private immutable weth;

	event DefaultConfigSet(address[] recipients, uint256[] shares, uint256 swapRecipientShare);
	event ConfigSet(bytes32 indexed configId, address[] recipients, uint256[] shares, uint256 swapRecipientShare);
	event ProfitDistributed(address plugin, bytes32 indexed configId, address token, address swapRecipient, uint256 amount);
	event ProfitDistributedZero(address plugin, bytes32 indexed configId, address token, address swapRecipient, uint256 amount);

	constructor(address _weth) {
		weth = _weth;
		address[] memory recipients = new address[](1);
		recipients[0] = msg.sender;
		uint256[] memory shares = new uint256[](1);
		shares[0] = 10000;

		ProfitShareConfig memory config = ProfitShareConfig({
			recipients: recipients,
			shares: shares,
			swapRecipientShare: 0
		});

		defaultConfig = config;
	}

	function initialize(address owner_) public initializer {
		_transferOwnership(owner_);
		address[] memory recipients = new address[](1);
		recipients[0] = msg.sender;
		uint256[] memory shares = new uint256[](1);
		shares[0] = 10000;

		ProfitShareConfig memory config = ProfitShareConfig({
			recipients: recipients,
			shares: shares,
			swapRecipientShare: 0
		});

		defaultConfig = config;
	}

	function setDefaultConfig(
		address[] memory recipients,
		uint256[] memory shares,
		uint256 swapRecipientShare
	) external onlyOwner {
		require(recipients.length == shares.length, "ProfitDistributor: recipients and shares length mismatch");
		require(recipients.length > 0, "ProfitDistributor: recipients cannot be empty");

		uint256 totalShares = 0;
		for (uint256 i = 0; i < shares.length; i++) {
			totalShares += shares[i];
		}
		require(
			totalShares + swapRecipientShare <= SHARE_DENOMINATOR,
			"ProfitDistributor: total shares exceed denominator"
		);

		defaultConfig = ProfitShareConfig({
			recipients: recipients,
			shares: shares,
			swapRecipientShare: swapRecipientShare
		});

		emit DefaultConfigSet(recipients, shares, swapRecipientShare);
	}

	function setConfig(
		bytes32 configId,
		address[] memory recipients,
		uint256[] memory shares,
		uint256 swapRecipientShare
	) external onlyOwner {
		require(recipients.length == shares.length, "ProfitDistributor: recipients and shares length mismatch");
		require(recipients.length > 0, "ProfitDistributor: recipients cannot be empty");

		uint256 totalShares = 0;
		for (uint256 i = 0; i < shares.length; i++) {
			totalShares += shares[i];
		}
		require(
			totalShares + swapRecipientShare <= SHARE_DENOMINATOR,
			"ProfitDistributor: total shares exceed denominator"
		);

		configs[configId] = ProfitShareConfig({
			recipients: recipients,
			shares: shares,
			swapRecipientShare: swapRecipientShare
		});

		emit ConfigSet(configId, recipients, shares, swapRecipientShare);
	}

	function distributeProfit(bytes32 configId, address token, address swapRecipient) external {
		if (token == address(0)) {
			distributeProfitETH(configId, swapRecipient);
		} else {
			distributeProfitERC20(configId, token, swapRecipient);
		}
	}

	/// @notice Distribute the entire balance of `token` among the configured recipients
	/// only, ignoring `swapRecipientShare`. The portion that would have been allocated to
	/// `swapRecipient` (plus rounding dust) is reassigned to the configured recipients
	/// pro-rata to their `shares` weights — the last recipient absorbs the remainder so
	/// the full balance is paid out in a single transfer per recipient.
	function distributeProfit(bytes32 configId, address token) external {
		if (token == address(0)) {
			distributeProfitETHNoSwapRecipient(configId);
		} else {
			distributeProfitERC20NoSwapRecipient(configId, token);
		}
	}

	function distributeProfitERC20NoSwapRecipient(bytes32 configId, address token) internal {
		ProfitShareConfig memory config;
		if (configs[configId].recipients.length == 0) {
			config = defaultConfig;
		} else {
			config = configs[configId];
		}

		uint256 amount = IERC20(token).balanceOf(address(this));

		if (amount == 1) {
			return;
		}

		if (amount == 0) {
			emit ProfitDistributedZero(msg.sender, configId, token, address(0), 0);
			return;
		}

		uint256 totalShares = 0;
		for (uint256 i = 0; i < config.shares.length; i++) {
			totalShares += config.shares[i];
		}
		if (totalShares == 0) return;

		uint256 remaining = amount;
		uint256 lastIndex = config.recipients.length - 1;
		for (uint256 i = 0; i < config.recipients.length; i++) {
			uint256 share = (i == lastIndex) ? remaining : (amount * config.shares[i]) / totalShares;
			remaining -= share;
			IERC20(token).safeTransfer(config.recipients[i], share);
		}

		emit ProfitDistributed(msg.sender, configId, token, address(0), amount);
	}

	function distributeProfitETHNoSwapRecipient(bytes32 configId) internal {
		ProfitShareConfig memory config;
		if (configs[configId].recipients.length == 0) {
			config = defaultConfig;
		} else {
			config = configs[configId];
		}

		uint256 value = address(this).balance;

		if (value == 1) {
			return;
		}

		if (value == 0) {
			emit ProfitDistributedZero(msg.sender, configId, address(0), address(0), 0);
			return;
		}

		uint256 totalShares = 0;
		for (uint256 i = 0; i < config.shares.length; i++) {
			totalShares += config.shares[i];
		}
		if (totalShares == 0) return;

		uint256 remaining = value;
		uint256 lastIndex = config.recipients.length - 1;
		for (uint256 i = 0; i < config.recipients.length; i++) {
			uint256 share = (i == lastIndex) ? remaining : (value * config.shares[i]) / totalShares;
			remaining -= share;
			(bool success, ) = config.recipients[i].call{value: share}("");
			require(success, "ETH transfer failed");
		}

		emit ProfitDistributed(msg.sender, configId, address(0), address(0), value);
	}

	function distributeProfitERC20(bytes32 configId, address token, address swapRecipient) internal {
		ProfitShareConfig memory config;
		if (configs[configId].recipients.length == 0) {
			config = defaultConfig;
		} else {
			config = configs[configId];
		}

		uint256 amount = IERC20(token).balanceOf(address(this));

		if (amount == 1) {
			return;
		}

		if (amount == 0) {
			emit ProfitDistributedZero(msg.sender, configId, token, swapRecipient, 0);
			return;
		}

		uint256[] memory amounts = new uint256[](config.recipients.length);
		uint256 totalDistributed = 0;

		// Distribute to main recipients
		for (uint256 i = 0; i < config.recipients.length; i++) {
			address recipient = config.recipients[i];
			uint256 share = (amount * config.shares[i]) / SHARE_DENOMINATOR;
			amounts[i] = share;
			totalDistributed += share;
			IERC20(token).safeTransfer(recipient, share);
		}

		// Distribute varied recipient share and any remaining dust
		uint256 variedAmount = 0;
		if (config.swapRecipientShare > 0) {
			// Calculate varied recipient's configured share
			uint256 variedShare = (amount * config.swapRecipientShare) / SHARE_DENOMINATOR;
			totalDistributed += variedShare;
			variedAmount += variedShare;

			// Add any remaining dust from rounding
			uint256 remainder = amount - totalDistributed;
			variedAmount += remainder;

			if (variedAmount > 0) {
				IERC20(token).safeTransfer(swapRecipient, variedAmount);
			}
		}

		emit ProfitDistributed(msg.sender, configId, token, swapRecipient, amount);
	}

	function distributeProfitETH(bytes32 configId, address swapRecipient) internal {
		ProfitShareConfig memory config;
		if (configs[configId].recipients.length == 0) {
			config = defaultConfig;
		} else {
			config = configs[configId];
		}

		uint256 value = address(this).balance;

		if (value == 1) {
			return;
		}

		if (value == 0) {
			emit ProfitDistributedZero(msg.sender, configId, address(0), swapRecipient, 0);
			return;
		}

		uint256[] memory amounts = new uint256[](config.recipients.length);
		uint256 totalDistributed = 0;

		// Distribute to main recipients
		for (uint256 i = 0; i < config.recipients.length; i++) {
			address recipient = config.recipients[i];
			uint256 share = (value * config.shares[i]) / SHARE_DENOMINATOR;
			amounts[i] = share;
			totalDistributed += share;
			(bool success, ) = recipient.call{value: share}("");
			require(success, "ETH transfer failed");
		}

		// Distribute varied recipient share and any remaining dust
		uint256 variedAmount = 0;
		if (config.swapRecipientShare > 0) {
			// Calculate varied recipient's configured share
			uint256 variedShare = (value * config.swapRecipientShare) / SHARE_DENOMINATOR;
			totalDistributed += variedShare;
			variedAmount += variedShare;

			// Add any remaining dust from rounding
			uint256 remainder = value - totalDistributed;
			variedAmount += remainder;

			if (variedAmount > 0) {
				(bool success, ) = swapRecipient.call{value: variedAmount}("");
				require(success, "ETH varied transfer failed");
			}
		}

		emit ProfitDistributed(msg.sender, configId, address(0), swapRecipient, value);
	}

	receive() external payable {}
}
