// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library DelegateCallLib {
    /**
     * @dev Handles the result of a delegatecall and reverts with the revert reason if the call failed.
     * @param success The success flag returned by the delegatecall.
     * @param result The result bytes returned by the delegatecall.
     * @return The result bytes if the delegatecall was successful.
     */
    function handleDelegateCallResult(bool success, bytes memory result) internal pure returns (bytes memory) {
        if (success) {
            return result;
        } else {
            // Check if there's any revert data. If not, revert with a generic message.
            if (result.length == 0) revert("delegatecall failed without a revert reason");

            // Forward the revert data from the delegatecall.
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
