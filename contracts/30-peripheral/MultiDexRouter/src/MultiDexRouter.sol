// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IMultiDexRouter} from "./interfaces/IMultiDexRouter.sol";
import {ISwapRouter} from "./interfaces/3rd/ISwapRouter.sol";
import {IV3Quoter, IV2Quoter} from "./interfaces/3rd/ISwapQuoter.sol";
import {PoolAddress} from "./libraries/PoolAddress.sol";
import {TransferHelper} from "./3rd/goplus/libs/TransferHelper.sol";
import {IERC20} from "@ozv5/token/ERC20/IERC20.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}

/// @title Multi-DEX Router
/// @notice A router that eases swapping tokens across multiple DEX protocols
/// @author The Flap Team
/// @dev This router provides a unified interface for swapping on different DEX platforms
contract MultiDexRouter is IMultiDexRouter {
    // Constructor parameters struct
    struct ConstructorParams {
        address weth;
        DEXConfig[] dexConfigs;
    }

    struct FeeTierConfig {
        uint8 enabled; // 8 bits
        uint24 v2FeeTier; // 24 bits
        uint24[3] v3FeeTiers; // 72 bits
    }

    struct DEXConfig {
        address v2Factory;
        bytes32 v2InitCodeHash;
        address v3Factory;
        address v3Deployer;
        address v3NonFungiblePositionManager;
        bytes32 v3InitCodeHash;
        bool isPancake;
        address v4Vault;
        address smartRouter;
        address v3Quoter;
        address v2SwapRouter;
        FeeTierConfig feeTiers;
    }

    // WETH address
    address private immutable WETH_ADDRESS;

    // DEX 0 immutables
    address private immutable DEX0_V2_FACTORY;
    bytes32 private immutable DEX0_V2_CODE_HASH;
    address private immutable DEX0_V3_FACTORY;
    address private immutable DEX0_V3_DEPLOYER;
    address private immutable DEX0_V3_NONFUNGIBLE_POSITION_MANAGER;
    bytes32 private immutable DEX0_V3_CODE_HASH;
    bool private immutable DEX0_IS_PANCAKE;
    address private immutable DEX0_V4_VAULT;
    address private immutable DEX0_SMART_ROUTER;
    address private immutable DEX0_V3_QUOTER;
    address private immutable DEX0_V2_SWAP_ROUTER;

    // DEX 1 immutables
    address private immutable DEX1_V2_FACTORY;
    bytes32 private immutable DEX1_V2_CODE_HASH;
    address private immutable DEX1_V3_FACTORY;
    address private immutable DEX1_V3_DEPLOYER;
    address private immutable DEX1_V3_NONFUNGIBLE_POSITION_MANAGER;
    bytes32 private immutable DEX1_V3_CODE_HASH;
    bool private immutable DEX1_IS_PANCAKE;
    address private immutable DEX1_V4_VAULT;
    address private immutable DEX1_SMART_ROUTER;
    address private immutable DEX1_V3_QUOTER;
    address private immutable DEX1_V2_SWAP_ROUTER;

    // DEX 2 immutables
    address private immutable DEX2_V2_FACTORY;
    bytes32 private immutable DEX2_V2_CODE_HASH;
    address private immutable DEX2_V3_FACTORY;
    address private immutable DEX2_V3_DEPLOYER;
    address private immutable DEX2_V3_NONFUNGIBLE_POSITION_MANAGER;
    bytes32 private immutable DEX2_V3_CODE_HASH;
    bool private immutable DEX2_IS_PANCAKE;
    address private immutable DEX2_V4_VAULT;
    address private immutable DEX2_SMART_ROUTER;
    address private immutable DEX2_V3_QUOTER;
    address private immutable DEX2_V2_SWAP_ROUTER;

    // Packed Fee Tiers
    uint256 private immutable DEX0_PACKED_FEE_TIERS;
    uint256 private immutable DEX1_PACKED_FEE_TIERS;
    uint256 private immutable DEX2_PACKED_FEE_TIERS;

    constructor(ConstructorParams memory params) {
        require(params.dexConfigs.length == 3, "Must provide exactly 3 DEX configurations");

        WETH_ADDRESS = params.weth;

        // DEX 0
        DEX0_V2_FACTORY = params.dexConfigs[0].v2Factory;
        DEX0_V2_CODE_HASH = params.dexConfigs[0].v2InitCodeHash;
        DEX0_V3_FACTORY = params.dexConfigs[0].v3Factory;
        DEX0_V3_DEPLOYER = params.dexConfigs[0].v3Deployer == address(0)
            ? params.dexConfigs[0].v3Factory
            : params.dexConfigs[0].v3Deployer;
        DEX0_V3_NONFUNGIBLE_POSITION_MANAGER = params.dexConfigs[0].v3NonFungiblePositionManager;
        DEX0_V3_CODE_HASH = params.dexConfigs[0].v3InitCodeHash;
        DEX0_IS_PANCAKE = params.dexConfigs[0].isPancake;
        DEX0_V4_VAULT = params.dexConfigs[0].v4Vault;
        DEX0_SMART_ROUTER = params.dexConfigs[0].smartRouter;
        DEX0_V3_QUOTER = params.dexConfigs[0].v3Quoter;
        DEX0_V2_SWAP_ROUTER = params.dexConfigs[0].v2SwapRouter;

        // DEX 1
        DEX1_V2_FACTORY = params.dexConfigs[1].v2Factory;
        DEX1_V2_CODE_HASH = params.dexConfigs[1].v2InitCodeHash;
        DEX1_V3_FACTORY = params.dexConfigs[1].v3Factory;
        DEX1_V3_DEPLOYER = params.dexConfigs[1].v3Deployer == address(0)
            ? params.dexConfigs[1].v3Factory
            : params.dexConfigs[1].v3Deployer;
        DEX1_V3_NONFUNGIBLE_POSITION_MANAGER = params.dexConfigs[1].v3NonFungiblePositionManager;
        DEX1_V3_CODE_HASH = params.dexConfigs[1].v3InitCodeHash;
        DEX1_IS_PANCAKE = params.dexConfigs[1].isPancake;
        DEX1_V4_VAULT = params.dexConfigs[1].v4Vault;
        DEX1_SMART_ROUTER = params.dexConfigs[1].smartRouter;
        DEX1_V3_QUOTER = params.dexConfigs[1].v3Quoter;
        DEX1_V2_SWAP_ROUTER = params.dexConfigs[1].v2SwapRouter;

        // DEX 2
        DEX2_V2_FACTORY = params.dexConfigs[2].v2Factory;
        DEX2_V2_CODE_HASH = params.dexConfigs[2].v2InitCodeHash;
        DEX2_V3_FACTORY = params.dexConfigs[2].v3Factory;
        DEX2_V3_DEPLOYER = params.dexConfigs[2].v3Deployer == address(0)
            ? params.dexConfigs[2].v3Factory
            : params.dexConfigs[2].v3Deployer;
        DEX2_V3_NONFUNGIBLE_POSITION_MANAGER = params.dexConfigs[2].v3NonFungiblePositionManager;
        DEX2_V3_CODE_HASH = params.dexConfigs[2].v3InitCodeHash;
        DEX2_IS_PANCAKE = params.dexConfigs[2].isPancake;
        DEX2_V4_VAULT = params.dexConfigs[2].v4Vault;
        DEX2_SMART_ROUTER = params.dexConfigs[2].smartRouter;
        DEX2_V3_QUOTER = params.dexConfigs[2].v3Quoter;
        DEX2_V2_SWAP_ROUTER = params.dexConfigs[2].v2SwapRouter;

        // Pack Fee Tiers
        DEX0_PACKED_FEE_TIERS = _packFeeTiers(params.dexConfigs[0].feeTiers);
        DEX1_PACKED_FEE_TIERS = _packFeeTiers(params.dexConfigs[1].feeTiers);
        DEX2_PACKED_FEE_TIERS = _packFeeTiers(params.dexConfigs[2].feeTiers);
    }

    /// @inheritdoc IMultiDexRouter
    function getDEXInfo(uint8 dexId) external view override returns (DEXInfo memory dexInfo) {
        if (dexId == 0) {
            dexInfo.v2InitCodeHash = DEX0_V2_CODE_HASH;
            dexInfo.v3InitCodeHash = DEX0_V3_CODE_HASH;
            dexInfo.v2Factory = DEX0_V2_FACTORY;
            dexInfo.v3Factory = DEX0_V3_FACTORY;
            dexInfo.v3Deployer = DEX0_V3_DEPLOYER;
            dexInfo.v4Vault = DEX0_V4_VAULT;
            dexInfo.v3SupportedFees = DEX0_IS_PANCAKE ? _getPancakeFees(0) : _getUniswapFees(0);
            dexInfo.smartRouter = DEX0_SMART_ROUTER;
            dexInfo.v3Quoter = DEX0_V3_QUOTER;
            dexInfo.v2SwapRouter = DEX0_V2_SWAP_ROUTER;
            dexInfo.nonfungiblePositionManager = DEX0_V3_NONFUNGIBLE_POSITION_MANAGER;
        } else if (dexId == 1) {
            dexInfo.v2InitCodeHash = DEX1_V2_CODE_HASH;
            dexInfo.v3InitCodeHash = DEX1_V3_CODE_HASH;
            dexInfo.v2Factory = DEX1_V2_FACTORY;
            dexInfo.v3Factory = DEX1_V3_FACTORY;
            dexInfo.v3Deployer = DEX1_V3_DEPLOYER;
            dexInfo.v4Vault = DEX1_V4_VAULT;
            dexInfo.v3SupportedFees = DEX1_IS_PANCAKE ? _getPancakeFees(1) : _getUniswapFees(1);
            dexInfo.smartRouter = DEX1_SMART_ROUTER;
            dexInfo.v3Quoter = DEX1_V3_QUOTER;
            dexInfo.v2SwapRouter = DEX1_V2_SWAP_ROUTER;
            dexInfo.nonfungiblePositionManager = DEX1_V3_NONFUNGIBLE_POSITION_MANAGER;
        } else if (dexId == 2) {
            dexInfo.v2InitCodeHash = DEX2_V2_CODE_HASH;
            dexInfo.v3InitCodeHash = DEX2_V3_CODE_HASH;
            dexInfo.v2Factory = DEX2_V2_FACTORY;
            dexInfo.v3Factory = DEX2_V3_FACTORY;
            dexInfo.v3Deployer = DEX2_V3_DEPLOYER;
            dexInfo.v4Vault = DEX2_V4_VAULT;
            dexInfo.v3SupportedFees = DEX2_IS_PANCAKE ? _getPancakeFees(2) : _getUniswapFees(2);
            dexInfo.smartRouter = DEX2_SMART_ROUTER;
            dexInfo.v3Quoter = DEX2_V3_QUOTER;
            dexInfo.v2SwapRouter = DEX2_V2_SWAP_ROUTER;
            dexInfo.nonfungiblePositionManager = DEX2_V3_NONFUNGIBLE_POSITION_MANAGER;
        } else {
            revert("Invalid DEX ID");
        }
    }

    /// @inheritdoc IMultiDexRouter
    function swapExactTokensForTokens(
        uint8 dexId,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external payable override returns (uint256 amountOut) {
        require(to != address(2) && to != address(this), "Invalid recipient");

        address smartRouter = _getSmartRouter(dexId);
        require(smartRouter != address(0), "Smart router not configured");
        address tokenIn = path[0];

        // Determine payer and actual amount
        address payer = amountIn > 0 ? msg.sender : address(this);
        uint256 actualAmountIn = amountIn > 0 ? amountIn : IERC20(tokenIn).balanceOf(address(this));

        // Pay the smart router
        pay(tokenIn, payer, smartRouter, actualAmountIn);

        // Execute swap with 0 as amountIn to use the router's balance
        amountOut = ISwapRouter(smartRouter).swapExactTokensForTokens(
            0, // Use router's balance
            amountOutMin,
            path,
            to
        );
    }

    /// @inheritdoc IMultiDexRouter
    function exactInputSingle(uint8 dexId, ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        require(params.recipient != address(2) && params.recipient != address(this), "Invalid recipient");

        address smartRouter = _getSmartRouter(dexId);
        require(smartRouter != address(0), "Smart router not configured");

        // Determine payer and actual amount
        address payer = params.amountIn > 0 ? msg.sender : address(this);
        uint256 actualAmountIn = params.amountIn > 0 ? params.amountIn : IERC20(params.tokenIn).balanceOf(address(this));

        // Pay the smart router
        pay(params.tokenIn, payer, smartRouter, actualAmountIn);

        // Prepare parameters for the smart router call
        ISwapRouter.ExactInputSingleParams memory routerParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.fee,
            recipient: params.recipient,
            amountIn: 0, // Use router's balance
            amountOutMinimum: params.amountOutMinimum,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });
        // Execute swap
        amountOut = ISwapRouter(smartRouter).exactInputSingle(routerParams);
    }

    /// @inheritdoc IMultiDexRouter
    function quoteExactInputSingle(uint8 dexId, QuoteExactInputSingleParams memory params)
        external
        override
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        address quoter = _getV3Quoter(dexId);

        IV3Quoter.QuoteExactInputSingleParams memory quoterParams = IV3Quoter.QuoteExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amountIn: params.amountIn,
            fee: params.fee,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        return IV3Quoter(quoter).quoteExactInputSingle(quoterParams);
    }

    /// @inheritdoc IMultiDexRouter
    function getAmountsOut(uint8 dexId, uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        address v2SwapRouter = _getV2SwapRouter(dexId);
        return IV2Quoter(v2SwapRouter).getAmountsOut(amountIn, path);
    }

    /// @inheritdoc IMultiDexRouter
    function computeV2PoolAddress(uint8 dexId, address tokenA, address tokenB)
        external
        view
        override
        returns (address pool)
    {
        (address factory, bytes32 codeHash) = _getV2FactoryAndCodeHash(dexId);
        return PoolAddress.computeV2Address(factory, codeHash, tokenA, tokenB);
    }

    /// @inheritdoc IMultiDexRouter
    function computeV3PoolAddress(uint8 dexId, address tokenA, address tokenB, uint24 fee)
        external
        view
        override
        returns (address pool)
    {
        (address deployer, bytes32 codeHash) = _getV3DeployerAndCodeHash(dexId);
        return PoolAddress.computeV3Address(deployer, codeHash, tokenA, tokenB, fee);
    }

    /// @inheritdoc IMultiDexRouter
    function getV2FactoryAddress(uint8 dexId) external view override returns (address factory) {
        (factory,) = _getV2FactoryAndCodeHash(dexId);
    }

    /// @inheritdoc IMultiDexRouter
    function getV3FactoryAddress(uint8 dexId) external view override returns (address factory) {
        (factory,) = _getV3FactoryAndCodeHash(dexId);
    }

    /// @inheritdoc IMultiDexRouter
    function getNonfungiblePositionManager(uint8 dexId) external view override returns (address positionManager) {
        if (dexId == 0) return DEX0_V3_NONFUNGIBLE_POSITION_MANAGER;
        if (dexId == 1) return DEX1_V3_NONFUNGIBLE_POSITION_MANAGER;
        if (dexId == 2) return DEX2_V3_NONFUNGIBLE_POSITION_MANAGER;
        revert("Invalid DEX ID");
    }

    /// @notice Handle payment to smart router
    /// @param token The token to pay
    /// @param payer The address paying (msg.sender or address(this))
    /// @param recipient The address receiving payment (smart router)
    /// @param value The amount to pay
    function pay(address token, address payer, address recipient, uint256 value) internal {
        if (token == WETH_ADDRESS && address(this).balance >= value) {
            // pay with WETH9
            IWETH(WETH_ADDRESS).deposit{value: value}(); // wrap only what is needed to pay
            IWETH(WETH_ADDRESS).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }

    /// @notice Get Pancake supported fee tiers
    function _getPancakeFees(uint8 dexId) private view returns (uint24[] memory fees) {
        uint256 packed = _getPackedFeeTiers(dexId);
        if ((packed & 0xFF) != 0) {
            // enabled
            fees = new uint24[](3);
            fees[0] = uint24(packed >> 32);
            fees[1] = uint24(packed >> 56);
            fees[2] = uint24(packed >> 80);
            return fees;
        }

        fees = new uint24[](4);
        fees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD)] = 2500;
        fees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_LOW)] = 100;
        fees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_HIGH)] = 10000;
        fees[3] = 500; // extra fee tier
    }

    /// @notice Get Uniswap supported fee tiers
    function _getUniswapFees(uint8 dexId) private view returns (uint24[] memory fees) {
        uint256 packed = _getPackedFeeTiers(dexId);
        if ((packed & 0xFF) != 0) {
            // enabled
            fees = new uint24[](3);
            fees[0] = uint24(packed >> 32);
            fees[1] = uint24(packed >> 56);
            fees[2] = uint24(packed >> 80);
            return fees;
        }

        fees = new uint24[](3);
        fees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD)] = 3000;
        fees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_LOW)] = 500;
        fees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_HIGH)] = 10000;
    }

    /// @notice Get smart router address for a DEX
    function _getSmartRouter(uint8 dexId) private view returns (address) {
        if (dexId == 0) return DEX0_SMART_ROUTER;
        if (dexId == 1) return DEX1_SMART_ROUTER;
        if (dexId == 2) return DEX2_SMART_ROUTER;
        revert("Invalid DEX ID");
    }

    /// @notice Get V3 quoter address for a DEX
    function _getV3Quoter(uint8 dexId) private view returns (address) {
        if (dexId == 0) return DEX0_V3_QUOTER;
        if (dexId == 1) return DEX1_V3_QUOTER;
        if (dexId == 2) return DEX2_V3_QUOTER;
        revert("Invalid DEX ID");
    }

    /// @notice Get V2 swap router address for a DEX
    function _getV2SwapRouter(uint8 dexId) private view returns (address) {
        if (dexId == 0) return DEX0_V2_SWAP_ROUTER;
        if (dexId == 1) return DEX1_V2_SWAP_ROUTER;
        if (dexId == 2) return DEX2_V2_SWAP_ROUTER;
        revert("Invalid DEX ID");
    }

    /// @notice Get V2 factory and code hash for a DEX
    function _getV2FactoryAndCodeHash(uint8 dexId) private view returns (address factory, bytes32 codeHash) {
        if (dexId == 0) return (DEX0_V2_FACTORY, DEX0_V2_CODE_HASH);
        if (dexId == 1) return (DEX1_V2_FACTORY, DEX1_V2_CODE_HASH);
        if (dexId == 2) return (DEX2_V2_FACTORY, DEX2_V2_CODE_HASH);
        revert("Invalid DEX ID");
    }

    /// @notice Get V3 factory and code hash for a DEX
    function _getV3FactoryAndCodeHash(uint8 dexId) private view returns (address factory, bytes32 codeHash) {
        if (dexId == 0) return (DEX0_V3_FACTORY, DEX0_V3_CODE_HASH);
        if (dexId == 1) return (DEX1_V3_FACTORY, DEX1_V3_CODE_HASH);
        if (dexId == 2) return (DEX2_V3_FACTORY, DEX2_V3_CODE_HASH);
        revert("Invalid DEX ID");
    }

    /// @notice Get V3 deployer and code hash for a DEX
    function _getV3DeployerAndCodeHash(uint8 dexId) private view returns (address deployer, bytes32 codeHash) {
        if (dexId == 0) return (DEX0_V3_DEPLOYER, DEX0_V3_CODE_HASH);
        if (dexId == 1) return (DEX1_V3_DEPLOYER, DEX1_V3_CODE_HASH);
        if (dexId == 2) return (DEX2_V3_DEPLOYER, DEX2_V3_CODE_HASH);
        revert("Invalid DEX ID");
    }

    /// @inheritdoc IMultiDexRouter
    function getV2PoolFeeTier(uint8 dexId) external view override returns (uint24 fee) {
        uint256 packed = _getPackedFeeTiers(dexId);
        if ((packed & 0xFF) != 0) {
            // enabled
            return uint24(packed >> 8);
        }

        if (dexId == 0) return DEX0_IS_PANCAKE ? 2500 : 3000;
        if (dexId == 1) return DEX1_IS_PANCAKE ? 2500 : 3000;
        if (dexId == 2) return DEX2_IS_PANCAKE ? 2500 : 3000;
        revert("Invalid DEX ID");
    }

    /// @inheritdoc IMultiDexRouter
    function getMajorPools(
        uint8 preferredDexId,
        IMultiDexRouter.V3LPFeeProfile preferredV3FeeTier,
        address baseToken,
        address quoteToken
    ) external view override returns (address[] memory pools) {
        // Validate preferredDexId
        require(preferredDexId <= 2, "Invalid preferred DEX ID");

        // Create temporary array to collect all pools
        // Max: suppose quote is not WETH
        //   Quote/Token Pools:   3 * 3 (V3) + 3 (V2) = 12
        //   WETH/Token pools:  2 * 3 (V3) + 3 (V2) = 9
        //   V4 pools: 3
        // => at most 24 pools
        address[] memory tempPools = new address[](24);
        uint256 poolCount = 0;

        // 1. Get preferred DEX V2/V3 pools with the specified fee tier
        address[] memory preferredPools =
            _getPreferredDexV2V3Pools(preferredDexId, preferredV3FeeTier, baseToken, quoteToken);

        // Revert if preferredPools is empty, that means preferredDexId is not available
        require(preferredPools.length > 0, "Preferred DEX not available");

        // Copy preferred DEX pools
        for (uint256 i = 0; i < preferredPools.length; i++) {
            tempPools[poolCount++] = preferredPools[i];
        }

        // 2. Get other DEX V2/V3 pools using standard fee tier
        // We use standard tier for other DEXes as it provides the best balance
        // between liquidity and fees for cross-DEX arbitrage
        for (uint8 dexId = 0; dexId <= 2; dexId++) {
            if (dexId == preferredDexId) continue;

            // Get V2/V3 pools for this DEX using standard fee tier
            address[] memory dexPools = _getPreferredDexV2V3Pools(
                dexId, IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD, baseToken, quoteToken
            );

            // Copy non-preferred DEX pools
            for (uint256 i = 0; i < dexPools.length; i++) {
                tempPools[poolCount++] = dexPools[i];
            }
        }

        // 3. Append all non-zero V4 pools (only once since V4 uses singleton pattern)
        // Check all DEXes for V4 support and add the first valid V4 pool found
        for (uint8 dexId = 0; dexId <= 2; dexId++) {
            address v4Vault = _getV4Vault(dexId);
            if (v4Vault != address(0)) {
                tempPools[poolCount++] = v4Vault;
                break; // Only add one V4 vault since they use singleton pattern
            }
        }

        // 4. Get WETH pools if quote token is not WETH (recursive call)
        if (quoteToken != WETH_ADDRESS) {
            // Recursively get major pools with WETH as quote token
            address[] memory wethPools = this.getMajorPools(preferredDexId, preferredV3FeeTier, baseToken, WETH_ADDRESS);

            // Copy WETH pools
            for (uint256 i = 0; i < wethPools.length; i++) {
                tempPools[poolCount++] = wethPools[i];
            }
        }

        // Create final result array with exact size
        pools = new address[](poolCount);
        for (uint256 i = 0; i < poolCount; i++) {
            pools[i] = tempPools[i];
        }
    }

    /// @notice Get preferred DEX V2/V3 pools
    /// @param dexId The DEX identifier
    /// @param preferredFeeTier The preferred V3 fee tier
    /// @param baseToken The base token address
    /// @param quoteToken The quote token address
    /// @return validPools Array of valid pool addresses for this DEX
    function _getPreferredDexV2V3Pools(
        uint8 dexId,
        IMultiDexRouter.V3LPFeeProfile preferredFeeTier,
        address baseToken,
        address quoteToken
    ) private view returns (address[] memory validPools) {
        // Get factory addresses directly instead of using getDEXInfo
        (address v2Factory,) = _getV2FactoryAndCodeHash(dexId);
        (address v3Factory,) = _getV3DeployerAndCodeHash(dexId);

        // If V2 factory is zero, return empty array (no pools for this DEX)
        // V2 is mandatory for all DEXes in this context
        if (v2Factory == address(0)) {
            return new address[](0);
        }

        // Create temporary array - max 4 pools: V2, V3 preferred, V3 other
        address[] memory tempPools = new address[](4);
        uint256 poolCount = 0;

        // Add V2 pool if V2 factory is available
        tempPools[poolCount++] = this.computeV2PoolAddress(dexId, baseToken, quoteToken);

        // Only add V3 pools if V3 factory is available
        if (v3Factory != address(0)) {
            // Get supported fees for this DEX
            uint24[] memory supportedFees = _getSupportedFees(dexId);

            // Add pools based on preferred fee tier
            if (preferredFeeTier == IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_LOW) {
                // Add 3 pools: [low, standard, high]
                tempPools[poolCount++] = this.computeV3PoolAddress(
                    dexId,
                    baseToken,
                    quoteToken,
                    supportedFees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_LOW)]
                );
                tempPools[poolCount++] = this.computeV3PoolAddress(
                    dexId,
                    baseToken,
                    quoteToken,
                    supportedFees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD)]
                );
                tempPools[poolCount++] = this.computeV3PoolAddress(
                    dexId,
                    baseToken,
                    quoteToken,
                    supportedFees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_HIGH)]
                );
            } else if (preferredFeeTier == IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD) {
                // Add 2 pools: [standard, high]
                tempPools[poolCount++] = this.computeV3PoolAddress(
                    dexId,
                    baseToken,
                    quoteToken,
                    supportedFees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD)]
                );
                tempPools[poolCount++] = this.computeV3PoolAddress(
                    dexId,
                    baseToken,
                    quoteToken,
                    supportedFees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_HIGH)]
                );
            } else if (preferredFeeTier == IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_HIGH) {
                // Add 2 pools: [high, standard]
                tempPools[poolCount++] = this.computeV3PoolAddress(
                    dexId,
                    baseToken,
                    quoteToken,
                    supportedFees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_HIGH)]
                );
                tempPools[poolCount++] = this.computeV3PoolAddress(
                    dexId,
                    baseToken,
                    quoteToken,
                    supportedFees[uint256(IMultiDexRouter.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD)]
                );
            }
        }

        // Create result array with exact size
        validPools = new address[](poolCount);
        for (uint256 i = 0; i < poolCount; i++) {
            validPools[i] = tempPools[i];
        }
    }

    /// @notice Get supported fees for a DEX
    /// @param dexId The DEX identifier
    /// @return fees Array of supported fee tiers
    function _getSupportedFees(uint8 dexId) private view returns (uint24[] memory fees) {
        if (dexId == 0) return DEX0_IS_PANCAKE ? _getPancakeFees(dexId) : _getUniswapFees(dexId);
        if (dexId == 1) return DEX1_IS_PANCAKE ? _getPancakeFees(dexId) : _getUniswapFees(dexId);
        if (dexId == 2) return DEX2_IS_PANCAKE ? _getPancakeFees(dexId) : _getUniswapFees(dexId);
        revert("Invalid DEX ID");
    }

    /// @notice Get V4 vault address for a DEX
    /// @param dexId The DEX identifier
    /// @return vault The V4 vault address
    function _getV4Vault(uint8 dexId) private view returns (address vault) {
        if (dexId == 0) return DEX0_V4_VAULT;
        if (dexId == 1) return DEX1_V4_VAULT;
        if (dexId == 2) return DEX2_V4_VAULT;
        revert("Invalid DEX ID");
    }

    /// @notice Pack fee tiers into a uint256
    function _packFeeTiers(FeeTierConfig memory config) private pure returns (uint256 packed) {
        packed = uint256(config.enabled);
        packed |= uint256(config.v2FeeTier) << 8;
        packed |= uint256(config.v3FeeTiers[0]) << 32;
        packed |= uint256(config.v3FeeTiers[1]) << 56;
        packed |= uint256(config.v3FeeTiers[2]) << 80;
    }

    /// @notice Get packed fee tiers for a DEX
    function _getPackedFeeTiers(uint8 dexId) private view returns (uint256) {
        if (dexId == 0) return DEX0_PACKED_FEE_TIERS;
        if (dexId == 1) return DEX1_PACKED_FEE_TIERS;
        if (dexId == 2) return DEX2_PACKED_FEE_TIERS;
        revert("Invalid DEX ID");
    }

    /// @notice Allow contract to receive ETH
    receive() external payable {}
}
