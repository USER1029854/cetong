// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IBribe, IBribe_Init} from "../VoterV5/BribeV2.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IPermissionsRegistry} from '../interfaces/IPermissionsRegistry.sol';
import {IVersionable} from "../interfaces/IVersionable.sol";
import {IUpgradeableBeacon, IBeaconFactory, IBeaconFactoryAdmin} from "./beacon-factory/IBeaconFactory.sol";

/**
 * @title BribeFactoryV4
 * @notice Beacon Factory contract to create BribeV2 contracts.
 * @dev 
 *  - WARN This factory acts an upgradeable beacon which has the ability to upgrade the implementation of all deployed contracts.
 *  - beaconFactoryAdmin MUST be a BeaconFactoryAdmin contract with the secureTimelockController set to
 *    a TimelockController with at least a 72 hour delay.
 */
contract BribeFactoryV4 is Ownable2StepUpgradeable, IBeaconFactory, IVersionable {
    /// @dev 4.1.0 Change the factory to a Beacon Proxy Factory
    /**
     * @dev changelog
     * - 4.1.0 Change the factory to a Beacon Proxy Factory
     * - 4.2.0 Add beaconFactoryAdmin protection (__gap reduced to [48])
     * - 4.3.0 Add UpgradeableBeaconForFactory to provide immutable access to the beacon implementation (__gap increased to [49])
     *      - WARN Cannot upgrade from 4.2.0 to 4.3.0 without a new factory (storage collision)
     */
    string public constant override VERSION = "4.3.0";

    address public last_bribe;
    address[] public bribes;
    address public voter;

    address[] public defaultRewardToken;
    mapping(address => bool) public defaultRewardTokens;

    IPermissionsRegistry public permissionsRegistry;
    /// @notice Immutable beacon contract for more secure access
    IUpgradeableBeacon private __upgradeableBeaconForFactory;

    /// @dev Gap to provide storage for future variables
    uint256[49] private __gap;

    event SetRegistry(address newRegistry);
    event SetVoter(address newVoter);
    event CreateBribe(address indexed bribe, string bribeType, address indexed rewardToken0, address indexed rewardToken1);

    modifier onlyAllowed() {
        require(owner() == msg.sender || permissionsRegistry.hasRole("BRIBE_ADMIN",msg.sender), 'ERR: BRIBE_ADMIN');
        _;
    }

    modifier onlySecureTimelock() {
        require(IPermissionsRegistry(permissionsRegistry).hasRole("SECURE_TIMELOCK", msg.sender), 'ERR: SECURE_TIMELOCK');
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _voter, 
        address _permissionsRegistry, 
        address _implementation,
        address _beaconFactoryAdmin
    ) initializer  public {
        __Ownable_init();   //after deploy ownership to multisig
        voter = _voter;
        // registry to check accesses
        permissionsRegistry = IPermissionsRegistry(_permissionsRegistry);

        require(isValidateBeaconImplementation(_implementation), 'invalid implementation');
        __upgradeableBeaconForFactory = IBeaconFactoryAdmin(_beaconFactoryAdmin).deployUpgradeableBeaconForFactory(
            "BribeFactoryV4",      // _beaconFactoryName
            IBeaconFactory(this),  // _beaconFactory
            _implementation       // _startingBeaconImplementation
        );
    }

    /// @notice Helper for verification
    function getBribeV2InitData(
        address _owner,
        address _voter,
        address _bribeFactory,
        string memory _type
    ) public pure returns (bytes memory) {
        return abi.encodeWithSelector(IBribe_Init.initialize.selector, _owner, _voter, _bribeFactory, _type);
    }

    /// @notice create a bribe contract
    /// @dev    _owner must be lynexTeamMultisig
    function createBribe(address _owner,address _token0,address _token1, string memory _type) external returns (address) {
        require(msg.sender == voter || msg.sender == owner(), 'only voter');

        bytes memory implementationData = getBribeV2InitData(_owner, voter, address(this), _type);

        BeaconProxy beaconProxy = new BeaconProxy(
            address(__upgradeableBeaconForFactory),
            implementationData
        );
        emit BeaconProxyData(address(beaconProxy), implementationData);

        IBribe lastBribe = IBribe(address(beaconProxy));

        if(_token0 != address(0)) lastBribe.addRewardToken(_token0);  
        if(_token1 != address(0)) lastBribe.addRewardToken(_token1); 

        lastBribe.addRewardTokens(defaultRewardToken);      
         
        last_bribe = address(lastBribe);
        bribes.push(last_bribe);
        emit CreateBribe(last_bribe, _type, _token0, _token1);
        return last_bribe;
    }

    /// @notice Get the total number of bribes created
    function bribesLength() external view returns (uint) {
        return bribes.length;
    }

    /// @notice Perform a check to see if a given implementation adheres to a valid interface for the factory
    function isValidateBeaconImplementation(address _newImplementation) public override(IBeaconFactory) view returns (bool) {
        return IBribe(_newImplementation).supportsInterface(type(IBribe).interfaceId);
    }

    /// @notice Address of the immutable contract which stores the implementation address for a beacon.
    function getUpgradeableBeaconForFactory() external override(IBeaconFactory) view returns (address) {
        return address(__upgradeableBeaconForFactory);
    }
    
    /// @notice Address of the implementation which will be used for the deployed BeaconProxy contracts.
    function getBeaconProxyImplementationForFactory() external override(IBeaconFactory) view returns (address) {
        return __upgradeableBeaconForFactory.implementation();
    }


    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */


    /// @notice set the bribe factory voter
    function setVoter(address _Voter) external {
        require(owner() == msg.sender, 'not owner');
        require(_Voter != address(0));
        voter = _Voter;
        emit SetVoter(voter);
    }

    
    /// @notice set the bribe factory permission registry
    function setPermissionsRegistry(address _permReg) external {
        require(owner() == msg.sender, 'not owner');
        require(_permReg != address(0));
        permissionsRegistry = IPermissionsRegistry(_permReg);
        emit SetRegistry(address(permissionsRegistry));
    }

    /// @notice set the bribe factory permission registry
    function pushDefaultRewardToken(address _token) external {
        require(owner() == msg.sender, 'not owner');
        require(!defaultRewardTokens[_token], 'duplicated token');
        require(_token != address(0));
        defaultRewardTokens[_token] = true;
        defaultRewardToken.push(_token);    
    }

    
    /// @notice set the bribe factory permission registry
    function removeDefaultRewardToken(address _token) external {
        require(owner() == msg.sender, 'not owner');
        require(_token != address(0));
        uint i = 0;
        for(i; i < defaultRewardToken.length; i++){
            if(defaultRewardToken[i] == _token){
                defaultRewardToken[i] = defaultRewardToken[defaultRewardToken.length -1];
                defaultRewardToken.pop();
                delete defaultRewardTokens[_token];
                break;
            }
        }    
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER or BRIBE ADMIN
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice Add a reward token to a given bribe
    function addRewardToBribe(address _token, address __bribe) external onlyAllowed {
        IBribe(__bribe).addRewardToken(_token);
    }

    /// @notice Add multiple reward token to a given bribe
    function addRewardsToBribe(address[] memory _tokens, address __bribe) external onlyAllowed {
        IBribe(__bribe).addRewardTokens(_tokens);
    }

    /// @notice Add a reward token to given bribes
    function addRewardToBribes(address _token, address[] memory __bribes) external onlyAllowed {
        uint i = 0;
        for ( i ; i < __bribes.length; i++){
            IBribe(__bribes[i]).addRewardToken(_token);
        }

    }

    /// @notice Add multiple reward tokens to given bribes
    function addRewardsToBribes(address[][] memory _token, address[] memory __bribes) external onlyAllowed {
        uint i = 0;
        uint k;
        for ( i ; i < __bribes.length; i++){
            address _br = __bribes[i];
            for(k = 0; k < _token.length; k++){
                IBribe(_br).addRewardToken(_token[i][k]);
            }
        }

    }

    /// @notice set a new voter in given bribes
    function setBribeVoter(address[] memory _bribe, address _voter) external onlyOwner {
        uint i = 0;
        for(i; i< _bribe.length; i++){
            IBribe(_bribe[i]).setVoter(_voter);
        }
    }

    /// @notice set a new minter in given bribes
    function setBribeMinter(address[] memory _bribe, address _minter) external onlyOwner {
        uint i = 0;
        for(i; i< _bribe.length; i++){
            IBribe(_bribe[i]).setMinter(_minter);
        }
    }

    /// @notice set a new owner in given bribes
    function setBribeOwner(address[] memory _bribe, address _owner) external onlyOwner {
        uint i = 0;
        for(i; i< _bribe.length; i++){
            IBribe(_bribe[i]).setOwner(_owner);
        }
    }

    /// @notice recover an ERC20 from bribe contracts.
    function recoverERC20From(address[] memory _bribe, address[] memory _tokens, uint[] memory _amounts) external onlyOwner {
        uint i = 0;
        require(_bribe.length == _tokens.length, 'mismatch len');
        require(_tokens.length == _amounts.length, 'mismatch len');

        for(i; i< _bribe.length; i++){
            if(_amounts[i] > 0) IBribe(_bribe[i]).emergencyRecoverERC20(_tokens[i], _amounts[i]);
        }
    }

     /// @notice recover an ERC20 from bribe contracts and update. 
    function recoverERC20AndUpdateData(address[] memory _bribe, address[] memory _tokens, uint[] memory _amounts) external onlyOwner {
        uint i = 0;
        require(_bribe.length == _tokens.length, 'mismatch len');
        require(_tokens.length == _amounts.length, 'mismatch len');

        for(i; i< _bribe.length; i++){
            if(_amounts[i] > 0) IBribe(_bribe[i]).recoverERC20AndUpdateData(_tokens[i], _amounts[i]);
        }
    }
}