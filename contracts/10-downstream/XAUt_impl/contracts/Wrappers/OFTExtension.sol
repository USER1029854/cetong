// SPDX-License-Identifier: Apache 2.0

pragma solidity 0.8.4;

import "contracts/Tether/TetherTokenV2.sol";
import {IERC7802, IERC165} from "contracts/Wrappers/interfaces/IERC7802.sol";

/*

   Copyright USDT0 2025

   Author Will Norden

   Licensed under the Apache License, Version 2.0
   http://www.apache.org/licenses/LICENSE-2.0

*/


contract TetherTokenOFTExtension is TetherTokenV2, IERC7802 {

  event LogSetOFTContract(address indexed oftContract);
  event Burn(address indexed from, uint256 amount);
  event LogUpdateNameAndSymbol(string name, string symbol);

  address public oftContract;

  string internal _newName;
  string internal _newSymbol;

  modifier onlyAuthorizedSender() {
    require(msg.sender == oftContract, "Only OFT can call");
    _;
  }

  function crosschainMint(address _destination, uint256 _amount) public override onlyAuthorizedSender {
    _mint(_destination, _amount);
    emit Mint(_destination, _amount);
    emit CrosschainMint(_destination, _amount, msg.sender);
  }

  function crosschainBurn(address _from, uint256 _amount) public override onlyAuthorizedSender {
    _burn(_from, _amount);
    emit Burn(_from, _amount);
    emit CrosschainBurn(_from, _amount, msg.sender);
  }

  function setOFTContract(address _oftContract) external onlyOwner {
    oftContract = _oftContract;
    emit LogSetOFTContract(_oftContract);
  }

  /**
  * @dev The hash of the name parameter for the EIP712 domain.
  *
  * NOTE: This function reads from storage by default, but can be redefined to return a constant value if gas costs
  * are a concern.
  */
  function _EIP712NameHash() internal virtual override view returns (bytes32) {
    return keccak256(bytes(name()));
  }

  function updateNameAndSymbol(string memory _name, string memory _symbol) public onlyOwner {
    _newName = _name;
    _newSymbol = _symbol;
    emit LogUpdateNameAndSymbol(_name, _symbol);
  }

  /**
  * @dev Returns the name of the token.
  */
  function name() public view virtual override returns (string memory) {
    return bytes(_newName).length == 0 ? super.name() : _newName;
  }

  /**
  * @dev Returns the symbol of the token, usually a shorter version of the
  * name.
  */
  function symbol() public view virtual override returns (string memory) {
    return bytes(_newSymbol).length == 0 ? super.symbol() : _newSymbol;
  }

  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return interfaceId == type(IERC7802).interfaceId || interfaceId == type(IERC165).interfaceId;
  }

  uint256[47] private __gap;
}
