// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library StringLib {
    /// @notice Concatenates two strings into a single string
    /// @param startString The initial string to start the concatenation
    /// @param additionalString The string to concatenate
    /// @return result The concatenated string
    function concatenateString(string memory startString, string memory additionalString) internal pure returns (string memory result) {
        result = string(abi.encodePacked(startString, additionalString));
    }

    /// @notice Return a string representation of a uint256
    function uint256ToString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint temp = value;
        uint digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}