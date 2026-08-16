// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVoterV5_GaugeLogic, IERC165} from "./IVoterV5_GaugeLogic.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IAlgebraFactory} from "@cryptoalgebra/v1-core/contracts/interfaces/IAlgebraFactory.sol";
import {IBribeFactory} from "../interfaces/IBribeFactory.sol";
import {IGaugeFactory} from "../interfaces/IGaugeFactory.sol";
import {IPermissionsRegistry} from "../interfaces/IPermissionsRegistry.sol";
import {IPoolEligibilityOracle} from "../interfaces/IPoolEligibilityOracle.sol";

import {IHypervisor} from "../interfaces/IHypervisor.sol";
import {IMultiPositionManager} from "../dex/uniswap-v4/IMultiPositionManager.sol";
import {IPairFactory} from "../interfaces/IPairFactory.sol";
import {IPairInfo} from "../interfaces/IPairInfo.sol";
import {IMetaMorpho} from "../interfaces/IMetaMorpho.sol";
import {IERC4626Like} from "../interfaces/IERC4626Like.sol";
import {VoterV5_Storage} from "./VoterV5_Storage.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {UniswapV3Helper} from "../libraries/UniswapV3Helper.sol";

/**
 * @notice Table showing GaugeType configurations
 * ┌──────────────────────┬──────────────────────────┬─────────────────────────────────┐
 * │      GaugeType       │       DEX Factory        │       Gauge Factory             │
 * ├──────────────────────┼──────────────────────────┼─────────────────────────────────┤
 * │    PAIR_CLASSIC      │   PairFactoryUpgradable  │          GaugeFactoryV2         │
 * │    ALM_ALGEBRA_V1    │     AlgebraFactory       │         GaugeFactoryV2_CL       │
 * │ ALM_ICHI_UNISWAP_V3  │     UniswapV3Factory     │         GaugeFactoryV2_CL       │
 * │ ALM_GAMMA_UNISWAP_V4 │   UniswapV4PoolManager   │         GaugeFactoryV2_CL       │
 * │    VAULT_MORPHO      │      No dex factory      │        GaugeFactoryMorpho       │
 * │  INCENTIVE_CAMPAIGN  │     AlgebraFactory       │  GaugeFactoryIncentiveCampaign  │
 * │    VAULT_EULER       │      No dex factory      │        GaugeFactoryEuler        │
 * └──────────────────────┴──────────────────────────┴─────────────────────────────────┘
 * 
 * @dev VAULT_MORPHO and VAULT_EULER both use the Gauge4626 implementation but have
 *      separate gauge types and factories to allow independent management.
 */

/// @notice Enum representing different gauge types
/// @dev Make sure to use the correct gaugeType or gauge creation will fail
enum GaugeType {
    PAIR_CLASSIC, // 0: Classic Stable/Volatile pair
    ALM_ALGEBRA_V1, // 1: Ichi/Gamma concentrated liquidity for Algebra
    ALM_ICHI_UNISWAP_V3, // 2: Ichi concentrated liquidity for UniswapV3
    ALM_GAMMA_UNISWAP_V4, // 3: Gamma concentrated liquidity for UniswapV4
    VAULT_MORPHO, // 4: Morpho MetaMorpho vaults
    INCENTIVE_CAMPAIGN, // 5: Incentivized campaign (rewards via external campaigns - Merkl, etc.)
    VAULT_EULER // 6: Euler vault products
}

/// @dev Deprecated aliases for backward compatibility
uint256 constant MORPHO = uint256(GaugeType.VAULT_MORPHO); // DEPRECATED: Use VAULT_MORPHO
uint256 constant EULER = uint256(GaugeType.VAULT_EULER);  // DEPRECATED: Use VAULT_EULER

/// @title VoterV5_GaugeLogic
/// @notice This contract contains the logic for creating gauges in the VoterV5 system. It is used to save contract
///  size in VoterV5 by separating out expensive logic.
/// @dev This contract MUST be called from VoterV5 through delegatecall().
contract VoterV5_GaugeLogic is IVoterV5_GaugeLogic, VoterV5_Storage, ERC165 {
    /// @notice Address of the pool eligibility oracle for permissionless gauge creation
    /// @dev Hardcoded to save storage space. If this needs to change, deploy a new VoterV5_GaugeLogic
    ///      and use VoterV5.setGaugeLogic() to update. Set to address(0) to disable permissionless creation.
    address public constant POOL_ELIGIBILITY_ORACLE = 0xC98FB7b58d4dA6C93c4A62bbEAA60932ABC96c33;

    /**
     * @notice changelog
     * - 1.1.0: Add Support for UniswapV3 and UniswapV4 Gauges
     * - 1.2.0: Add Support for Morpho Gauges
     * - 1.3.0: Add Support for Incentive Campaign Gauges
     * - 1.4.0: Add Support for Euler Gauges
     * - 1.5.0: Rename MORPHO to VAULT_ERC4626, remove EULER enum (MORPHO/EULER now constants)
     * - 1.6.0: Split VAULT_ERC4626 into VAULT_MORPHO(4) and VAULT_EULER(6) for independent management
     * - 1.7.0: Add permissionless gauge creation for INCENTIVE_CAMPAIGN gauges with pool eligibility oracle
     */
    string public constant VERSION_GAUGE_LOGIC = "1.7.0";

    /// @notice Maximum valid gauge type enum value
    uint256 public constant MAX_GAUGE_TYPE = uint256(type(GaugeType).max);

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        return interfaceId == type(IVoterV5_GaugeLogic).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Validate if gauge type is within enum bounds (pure function)
    function isValidGaugeType(uint256 _gaugeType) public pure returns (bool) {
        return _gaugeType <= MAX_GAUGE_TYPE;
    }

    struct _CreateGauge_LocalVars {
        address tokenA;
        address tokenB;
        address rewardToken;
        address dexFactory;
        address gaugeFactory;
        address internal_bribe;
        address external_bribe;
        bool isPair;
    }

    /// @notice create a gauge
    /// @param  _pool       LP address, which varies based on gauge type:
    ///                     - For PAIR_CLASSIC: The actual pair contract address (similar to UniswapV2 pairs)
    ///                     - For ALM strategies (GAMMA): The strategy contract address that manages the position
    ///                     - For VAULT_ERC4626: Any ERC4626 vault address (Morpho, Euler, Aave, Compound, etc.)
    ///                     - For INCENTIVE_CAMPAIGN: The Algebra pool address
    /// @param  _gaugeType  enum GaugeType, the type of gauge to create. The associated factory (_factories[_gaugeType])
    ///                     represents different things based on type:
    ///                     - For PAIR_CLASSIC: Deploy a Gauge for Solidly Classic Pairs
    ///                     - For ALM_GAMMA_ALGEBRA: Deploy a Gauge for Gamma + Algebra ALM strategies
    ///                     - For ALM_GAMMA_UNISWAP_V3: Deploy a Gauge for Gamma + UniswapV3 ALM strategies
    ///                     - For ALM_GAMMA_UNISWAP_V4: Deploy a Gauge for Gamma + UniswapV4 ALM strategies
    ///                     - For VAULT_ERC4626: Deploy a Gauge4626 for any ERC4626 vault
    ///                     - For INCENTIVE_CAMPAIGN: Deploy a Gauge for Algebra pools
    function createGauge(
        address _pool,
        uint256 _gaugeType
    ) external override returns (address _gauge, address _internal_bribe, address _external_bribe) {
        // Enhanced validation
        require(_gaugeType <= MAX_GAUGE_TYPE, "Invalid gauge type enum");
        require(_gaugeType < _factories.length, "Gauge type not configured");
        require(gauges[_pool] == address(0), "!exists");
        require(_pool.code.length > 0, "!contract");

        _CreateGauge_LocalVars memory vars;
        vars.dexFactory = _factories[_gaugeType];
        vars.gaugeFactory = _gaugeFactories[_gaugeType];

        // ERC4626 vault gauges don't need a dexFactory
        bool isVaultGauge = _gaugeType == uint256(GaugeType.VAULT_MORPHO) || _gaugeType == uint256(GaugeType.VAULT_EULER);
        
        if (!isVaultGauge) {
            require(vars.dexFactory != address(0), "dex factory not set");
        }
        require(vars.gaugeFactory != address(0), "gauge factory not set");

        if (_gaugeType == uint256(GaugeType.PAIR_CLASSIC)) {
            /**
             * @dev Classic Stable/Volatile pair
             */
            (vars.tokenA) = IPairInfo(_pool).token0();
            (vars.tokenB) = IPairInfo(_pool).token1();
            vars.isPair = IPairFactory(vars.dexFactory).isPair(_pool);
        } else if (_gaugeType == uint256(GaugeType.ALM_ALGEBRA_V1)) {
            /**
             * @dev ICHI/GAMMA + Algebra ALM strategy
             */
            (vars.tokenA) = IPairInfo(_pool).token0();
            (vars.tokenB) = IPairInfo(_pool).token1();
            address _pool_factory = IAlgebraFactory(vars.dexFactory).poolByPair(vars.tokenA, vars.tokenB);
            address _pool_hyper = IHypervisor(_pool).pool();
            require(_pool_hyper == _pool_factory, "wrong tokens");
            vars.isPair = true;
        } else if (_gaugeType == uint256(GaugeType.ALM_ICHI_UNISWAP_V3)) {
            /**
             * @dev ICHI + Uniswap V3 ALM strategy
             */
            (vars.tokenA) = IPairInfo(_pool).token0();
            (vars.tokenB) = IPairInfo(_pool).token1();
            address _pool_hyper = IHypervisor(_pool).pool();
            bool isValidPool = UniswapV3Helper.validatePoolExists(
                vars.dexFactory,
                vars.tokenA,
                vars.tokenB,
                _pool_hyper
            );
            require(isValidPool, "wrong tokens");
            vars.isPair = true;
        } else if (_gaugeType == uint256(GaugeType.ALM_GAMMA_UNISWAP_V4)) {
            /**
             * @dev GAMMA + Uniswap V4 ALM strategy
             */
            (vars.tokenA) = IPairInfo(_pool).token0();
            (vars.tokenB) = IPairInfo(_pool).token1();
            address _poolManager = IMultiPositionManager(_pool).poolManager();
            require(_poolManager == vars.dexFactory, "!poolManager");
            /// @dev IMultiPositionManager supports token0() and token1()
            // vars.tokenA = address(IMultiPositionManager(_pool).token0());
            // vars.tokenB = address(IMultiPositionManager(_pool).token1());
            vars.isPair = true;
        } else if (_gaugeType == uint256(GaugeType.VAULT_MORPHO) || _gaugeType == uint256(GaugeType.VAULT_EULER)) {
            /**
             * @dev ERC4626 vault - single asset vault
             * Unified handling for all ERC4626-compatible vaults (Morpho, Euler, Aave, Compound, etc.)
             * Note: IMetaMorpho extends IERC4626, so we can use the standard interface for all
             */
            address asset = IERC4626Like(_pool).asset();
            vars.tokenA = asset;
            vars.isPair = false;
        } else if (_gaugeType == uint256(GaugeType.INCENTIVE_CAMPAIGN)) {
            /**
             * @dev Algebra manual position pools - incentive campaign gauge
             */
            vars.tokenA = IPairInfo(_pool).token0();
            vars.tokenB = IPairInfo(_pool).token1();
            address _pool_factory = IAlgebraFactory(vars.dexFactory).poolByPair(vars.tokenA, vars.tokenB);
            require(_pool == _pool_factory && _pool_factory != address(0), "invalid Algebra pool");
            vars.isPair = true;
        }

        /// @dev Gov can create for any pool, even non-lynex pairs
        bool isGov = IPermissionsRegistry(permissionRegistry).hasRole("GOVERNANCE", msg.sender);
        
        if (!isGov) {
            // ERC4626 vault gauges are single-asset vaults (not pairs) - allow them
            if (!isVaultGauge) {
                require(vars.isPair, "!_pool");
            }

            if (_gaugeType == uint256(GaugeType.INCENTIVE_CAMPAIGN)) {
                /// @dev INCENTIVE_CAMPAIGN gauges can be created permissionlessly if pool is eligible
                require(
                    IPoolEligibilityOracle(POOL_ELIGIBILITY_ORACLE).canCreateGauge(_pool),
                    "pool not eligible"
                );
            } else if (_gaugeType != uint256(GaugeType.PAIR_CLASSIC)) {
                /// @dev Non-classic, non-campaign pairs need to be whitelisted
                require(isWhitelistedPool[_pool], "Only whitelisted pools");
            }

            /// @dev Token validation based on gauge type
            if (isVaultGauge) {
                /// @dev For ERC4626 vaults, tokenA is the only asset
                require(vars.tokenA != address(0), "!vault.asset");
                require(isWhitelisted[vars.tokenA], "!whitelistedAsset");
            } else if (_gaugeType == uint256(GaugeType.INCENTIVE_CAMPAIGN)) {
                /// @dev Incentive campaign gauges require at least one whitelisted token
                require(vars.tokenA != address(0), "!pool.tokenA");
                require(vars.tokenB != address(0), "!pool.tokenB");
                require(
                    isWhitelisted[vars.tokenA] || isWhitelisted[vars.tokenB],
                    "At least one token must be whitelisted"
                );
            } else if (_gaugeType == uint256(GaugeType.ALM_GAMMA_UNISWAP_V4)) {
                /// @dev UniswapV4 supports native tokens at address(0)
                if (vars.tokenA != address(0)) {
                    require(isWhitelisted[vars.tokenA], "!whitelistedA");
                }
                require(isWhitelisted[vars.tokenB], "!whitelistedB");
                require(vars.tokenB != address(0), "!pair.tokenB");
            } else {
                /// @dev Standard pair validation
                require(isWhitelisted[vars.tokenA], "!whitelistedA");
                require(isWhitelisted[vars.tokenB], "!whitelistedB");
                require(vars.tokenA != address(0), "!pair.tokenA");
                require(vars.tokenB != address(0), "!pair.tokenB");
            }
        }

        /// -----------------------------------------------------------------------
        /// Setup Bribes
        /// -----------------------------------------------------------------------

        // create internal and external bribe
        address _owner = IPermissionsRegistry(permissionRegistry).teamMultisig();
        string memory _type;
        
        // Algebra pools (INCENTIVE_CAMPAIGN) don't have a symbol, so construct from token symbols
        if (_gaugeType == uint256(GaugeType.INCENTIVE_CAMPAIGN)) {
            _type = string.concat(protocolName, " LP Fees: ", IERC20(vars.tokenA).symbol(), "/", IERC20(vars.tokenB).symbol());
        } else {
            _type = string.concat(protocolName, " LP Fees: ", IERC20(_pool).symbol());
        }
        vars.internal_bribe = IBribeFactory(bribefactory).createBribe(_owner, vars.tokenA, vars.tokenB, _type);

        if (_gaugeType == uint256(GaugeType.INCENTIVE_CAMPAIGN)) {
            _type = string.concat(protocolName, " Bribes: ", IERC20(vars.tokenA).symbol(), "/", IERC20(vars.tokenB).symbol());
        } else {
            _type = string.concat(protocolName, " Bribes: ", IERC20(_pool).symbol());
        }
        vars.external_bribe = IBribeFactory(bribefactory).createBribe(_owner, vars.tokenA, vars.tokenB, _type);

        /// -----------------------------------------------------------------------
        /// Setup Gauge
        /// -----------------------------------------------------------------------

        vars.rewardToken = oToken != address(0) ? oToken : base;

        _gauge = IGaugeFactory(vars.gaugeFactory).createGaugeV2(
            vars.rewardToken,
            _ve,
            _pool,
            address(this), // distribution address
            vars.internal_bribe,
            vars.external_bribe,
            vars.isPair
        );
        // approve spending for protocol token, this is set back to zero if gauge is killed
        IERC20(vars.rewardToken).approve(_gauge, type(uint256).max);

        /// -----------------------------------------------------------------------
        /// Save Gauge Data
        /// -----------------------------------------------------------------------

        internal_bribes[_gauge] = vars.internal_bribe;
        external_bribes[_gauge] = vars.external_bribe;
        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        pools.push(_pool);

        // update supplyIndex (gaugeRewardsPerVoteWeight) gauge => index (globalRewardsPerVoteWeight)
        supplyIndex[_gauge] = index; // new gauges are set to the default global state

        return (_gauge, vars.internal_bribe, vars.external_bribe);
    }
}
