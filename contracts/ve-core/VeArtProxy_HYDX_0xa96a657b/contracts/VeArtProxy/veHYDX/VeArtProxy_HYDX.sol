// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Base64} from "../../libraries/Base64.sol";
import {IVeArtProxyHydrex} from "../IVeArtProxyHydrex.sol";
import {StringLib} from "../StringLib.sol";
import {IVotingEscrowV2_Data} from "../../VoterV5/VotingEscrow/IVotingEscrowV2_Data.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract VeArtProxy_HYDX is IVeArtProxyHydrex, OwnableUpgradeable {
    using StringLib for uint256;
    using StringLib for string;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    string public protocolName;

    /**
     * @dev Storage gap to allow for upgrades
     */
    uint256[49] private __gap;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

    function initialize(string memory _protocolName) public initializer {
        __Ownable_init();
        protocolName = _protocolName;
    }

    /// -----------------------------------------------------------------------
    /// Public Functions
    /// -----------------------------------------------------------------------

    function tokenURI(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 _value,
        IVotingEscrowV2_Data.LockType _lockType
    ) external view override returns (string memory output) {
        return _tokenURI(_tokenId, _balanceOf, _locked_end, _value, _lockType);
    }

    function _tokenURI(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 _value,
        IVotingEscrowV2_Data.LockType _lockType
    ) public view override returns (string memory output) {
        string memory svgCard = _buildSvgCardFromDetails(_tokenId, _balanceOf, _locked_end, _value, _lockType);

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "Hydrex Lock #',
                        _tokenId.uint256ToString(),
                        '", "description": "',
                        protocolName,
                        ' accounts/locks, can be used to vote on token emission, earn protocol fees, and receive bribes", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(svgCard)),
                        '"}'
                    )
                )
            )
        );
        output = string(abi.encodePacked("data:application/json;base64,", json));
    }

    /// -----------------------------------------------------------------------
    /// SVG Generation Functions
    /// -----------------------------------------------------------------------

    function _buildSvgCardFromDetails(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 _value,
        IVotingEscrowV2_Data.LockType _lockType
    ) internal pure returns (string memory svgCard) {
        (string memory svgHead, string memory svgEnd) = _createSvgWrapper();
        svgCard = svgHead
            .concatenateString(_createSVGCardBase())
            .concatenateString(_createCenteredHYDXLogo())
            .concatenateString(_createGenerativeArt(_tokenId, _balanceOf, _locked_end, _value))
            .concatenateString(_createCardText(_tokenId, _balanceOf, _locked_end, _value, _lockType))
            .concatenateString(svgEnd);
    }

    function _createSvgWrapper() internal pure returns (string memory svgHead, string memory svgEnd) {
        svgHead = '<svg width="1000" height="1200" viewBox="0 0 1000 1200" fill="none" xmlns="http://www.w3.org/2000/svg">';
        svgEnd = "</svg>";
    }

    function _createSVGCardBase() internal pure returns (string memory svgSection) {
        string
            memory svgCardEffects = '<defs><linearGradient id="backgroundGradient" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" style="stop-color:#0052FF;stop-opacity:1" /><stop offset="50%" style="stop-color:#0066FF;stop-opacity:1" /><stop offset="100%" style="stop-color:#003DD6;stop-opacity:1" /></linearGradient><filter id="blurFilter_0" x="65.0156" y="-361.898" width="1508.16" height="1292.46" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape"/><feGaussianBlur stdDeviation="250" result="effect1_foregroundBlur_10553_6450"/></filter><filter id="blurFilter_1" x="-737.984" y="584.102" width="1508.16" height="1292.46" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape"/><feGaussianBlur stdDeviation="250" result="effect1_foregroundBlur_10553_6450"/></filter><clipPath id="clipPath0"><rect width="1000" height="1200" rx="60" fill="white"/></clipPath></defs>';

        string
            memory svgCardBase = '<g clip-path="url(#clipPath)"><rect width="1000" height="1200" rx="60" fill="url(#backgroundGradient)"/><rect x="64" y="64" width="872" height="702" rx="26" stroke="white" stroke-width="8"/><g opacity="0.45" filter="url(#blurFilter_0)"><ellipse cx="819.098" cy="284.331" rx="257.274" ry="140.46" transform="rotate(-10.8389 819.098 284.331)" fill="#0099CC"/></g><g opacity="0.45" filter="url(#blurFilter_1)"><ellipse cx="16.0976" cy="1230.33" rx="257.274" ry="140.46" transform="rotate(-10.8389 16.0976 1230.33)" fill="#0099CC"/></g></g>';

        svgSection = svgCardEffects.concatenateString(svgCardBase);
    }

    function _createCenteredHYDXLogo() internal pure returns (string memory svgSection) {
        string
            memory logoSvg = '<g transform="translate(280, 180) scale(2.5)"><path d="M156.803 60.4574C154.296 59.0993 151.654 58.0981 148.937 57.4356C144.042 56.2137 138.79 56.1401 133.983 54.5611C127.015 52.3748 121.343 46.5669 119.304 39.5553C117.71 34.3252 117.736 28.635 116.128 23.4049C114.328 17.2877 110.581 11.6601 105.649 7.5673C99.7193 2.52121 92.207 0 84.6764 0C77.3371 0 69.9868 2.39607 64.0794 7.1882C50.1885 17.8693 47.3287 39.0069 57.9106 52.8496C60.822 56.7842 64.6756 60.0415 69.0188 62.3308C67.7416 63.2583 66.516 64.2963 65.3639 65.4483C64.2192 66.593 63.1813 67.8149 62.2464 69.0958C60.2331 65.2716 57.4542 61.8266 54.1379 59.0735C48.212 54.0274 40.6998 51.5025 33.1691 51.5025C25.8299 51.5025 18.4796 53.8986 12.5721 58.6907C-1.31875 69.3718 -4.17863 90.5094 6.4033 104.352C10.8311 110.337 17.4269 114.772 24.63 116.568C29.621 117.871 34.9874 117.911 39.8937 119.509C46.9017 121.691 52.6178 127.544 54.6532 134.596C56.258 139.929 56.2027 145.737 57.9179 151.059C58.6872 153.536 59.7656 155.947 61.1348 158.214C67.3 168.623 78.2831 174 89.3361 174C98.4421 174 107.596 170.349 114.136 162.855L114.188 162.8C128.256 147.209 123.912 121.868 105.292 111.964C105.167 111.897 105.042 111.835 104.916 111.769C106.197 110.834 107.419 109.796 108.564 108.655C109.709 107.514 110.75 106.284 111.678 105.011C111.98 105.589 112.3 106.156 112.638 106.719C118.804 117.127 129.787 122.505 140.84 122.505C149.946 122.505 159.1 118.854 165.64 111.36L165.692 111.305C179.759 95.7138 175.416 70.3729 156.795 60.4684L156.803 60.4574ZM75.7765 98.2387C72.7878 95.25 71.1426 91.275 71.1426 87.046C71.1426 82.817 72.7878 78.8456 75.7765 75.8533C78.8609 72.769 82.9134 71.2268 86.9695 71.2268C91.0256 71.2268 95.0743 72.769 98.1624 75.8533C104.335 82.0257 104.335 92.0663 98.1624 98.235C95.1737 101.224 91.1985 102.873 86.9695 102.873C82.7404 102.873 78.7689 101.227 75.7765 98.235V98.2387ZM107.493 137.731C108.476 143.326 106.933 148.865 103.264 152.936C103.238 152.965 103.212 152.991 103.186 153.021L103.135 153.076C103.105 153.109 103.076 153.142 103.05 153.172C98.4163 158.483 92.4721 159.274 89.3435 159.274C82.7919 159.274 76.9875 156.072 73.8074 150.709C73.7853 150.672 73.7632 150.632 73.7374 150.595C72.994 149.366 72.4051 148.052 71.9818 146.69C71.967 146.642 71.9523 146.594 71.9376 146.546C71.437 144.99 71.1205 142.796 70.7856 140.477C70.3512 137.459 69.858 134.04 68.7796 130.429C65.3603 118.688 56.0187 109.141 44.3657 105.478C40.4789 104.223 36.8167 103.701 33.5814 103.237C31.6306 102.957 29.7866 102.696 28.3585 102.324C28.307 102.309 28.2554 102.298 28.2039 102.284C24.3576 101.323 20.6328 98.8239 18.244 95.5923C18.1998 95.5298 18.152 95.4709 18.1041 95.4083C12.458 88.025 14.0996 76.0852 21.5492 70.3619C21.6486 70.2846 21.7517 70.2036 21.8511 70.1226C24.9502 67.6088 28.9732 66.2249 33.1728 66.2249C37.4681 66.2249 41.5242 67.664 44.5939 70.2809C44.6418 70.3214 44.6896 70.3619 44.7375 70.4024C47.4354 72.6402 49.5334 75.7981 50.4977 79.0665C50.5161 79.1254 50.5308 79.1806 50.5492 79.2395C51.0204 80.7743 51.3259 82.8906 51.6498 85.1284C52.0878 88.1723 52.5846 91.6136 53.6852 95.2574C57.1082 106.918 66.4019 116.417 77.9702 120.079C81.8865 121.356 85.5782 121.886 88.8392 122.354C90.709 122.623 92.4721 122.877 93.8633 123.223C93.8891 123.23 93.9186 123.237 93.9443 123.245C95.4755 123.616 96.933 124.176 98.2728 124.901C98.3059 124.919 98.3427 124.938 98.3795 124.956C103.19 127.514 106.51 132.174 107.486 137.731H107.493ZM154.767 101.433C154.742 101.463 154.716 101.489 154.69 101.518L154.639 101.573C154.609 101.606 154.58 101.640 154.554 101.669C149.92 106.98 143.976 107.771 140.847 107.771C134.295 107.771 128.491 104.569 125.311 99.2067C125.289 99.1699 125.267 99.1294 125.241 99.0926C124.498 97.8633 123.909 96.5493 123.485 95.1875C123.471 95.1396 123.456 95.0918 123.441 95.0439C122.941 93.487 122.624 91.2934 122.289 88.9746C121.855 85.9566 121.362 82.5373 120.283 78.9266C116.864 67.1855 107.522 57.6381 95.8693 53.9759C91.9825 52.7208 88.3203 52.1982 85.0849 51.7344C83.1342 51.4547 81.2902 51.1934 79.8621 50.8179C79.8106 50.8032 79.759 50.7922 79.7075 50.7775C75.8612 49.8168 72.1364 47.3177 69.7476 44.0861C69.7034 44.0236 69.6556 43.9647 69.6077 43.9021C63.9616 36.5188 65.6032 24.579 73.0528 18.8557C73.1559 18.7784 73.2553 18.6974 73.3547 18.6164C76.4538 16.1026 80.4768 14.7187 84.6764 14.7187C88.9717 14.7187 93.0278 16.1578 96.0975 18.7747C96.1454 18.8152 96.1932 18.8557 96.2411 18.8962C98.939 21.134 101.037 24.2919 102.001 27.5603C102.02 27.6192 102.034 27.6744 102.053 27.7333C102.524 29.2681 102.829 31.3844 103.153 33.6222C103.591 36.6661 104.092 40.1148 105.192 43.7586C108.619 55.415 117.909 64.9109 129.474 68.5768C133.39 69.854 137.082 70.384 140.343 70.8514C142.209 71.1201 143.976 71.374 145.367 71.72C145.393 71.7274 145.422 71.7347 145.452 71.7421C146.983 72.1138 148.44 72.6733 149.78 73.3984C149.813 73.4168 149.85 73.4352 149.887 73.4536C154.697 76.0116 158.017 80.6712 158.993 86.2289C159.976 91.8234 158.433 97.3627 154.764 101.433H154.767Z" fill="white"/></g>';
        svgSection = logoSvg;
    }

    function _createGenerativeArt(
        uint256 _tokenId,
        uint256 /* _balanceOf */,
        uint256 /* _locked_end */,
        uint256 /* _value */
    ) internal pure returns (string memory svgSection) {
        // Generate deterministic pattern in top left based on token ID
        string memory topLeftPattern = _createTokenPattern(_tokenId);

        svgSection = topLeftPattern;
    }

    function _createTokenPattern(uint256 _tokenId) internal pure returns (string memory) {
        string memory pattern = "";
        uint256 seed = uint256(keccak256(abi.encodePacked(_tokenId)));

        for (uint256 row = 0; row < 6; row++) {
            for (uint256 col = 0; col < 6; col++) {
                uint256 x = 80 + (col * 14);
                uint256 y = 80 + (row * 14);

                uint256 cellSeed = (seed >> ((row * 6 + col) % 256)) & 0xFF;

                if (cellSeed > 127) {
                    uint256 opacity = 30 + ((cellSeed % 70));

                    pattern = pattern.concatenateString(
                        string(
                            abi.encodePacked(
                                '<rect x="',
                                x.uint256ToString(),
                                '" y="',
                                y.uint256ToString(),
                                '" width="12" height="12" fill="white" opacity="0.',
                                (opacity < 10 ? "0" : ""),
                                opacity.uint256ToString(),
                                '"/>'
                            )
                        )
                    );
                }
            }
        }

        return pattern;
    }

    function _createCardText(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 /* _value */,
        IVotingEscrowV2_Data.LockType _lockType
    ) internal pure returns (string memory svgSection) {
        string memory textStyles = "<style>.text { fill: white; font-family: Helvetica; font-size: 42px; }</style>";

        // Determine account type based on LockType and unlock timestamp
        string memory accountType;
        if (_lockType == IVotingEscrowV2_Data.LockType.PERMANENT) {
            accountType = "Protocol";
        } else if (_lockType == IVotingEscrowV2_Data.LockType.ROLLING) {
            accountType = "Flex (Rolling)";
        } else {
            accountType = "Flex";
        }

        // Calculate earning power (1.3 * active voting power, using _balanceOf as proxy)
        uint256 earningPower = (_balanceOf * 13) / 10; // 1.3x
        uint256 formattedEarningPower = earningPower / 10 ** 18;

        string memory textTokenId = _createCardTextLine("TOKEN ID", _tokenId.uint256ToString(), 860);
        string memory textAccountType = _createCardTextLine("ACCOUNT TYPE", accountType, 947);
        string memory textUnlockTimestamp = _createCardTextLine(
            "UNLOCK TIMESTAMP",
            _locked_end.uint256ToString(),
            1034
        );
        string memory textEarningPower = _createCardTextLine(
            "EARNING POWER",
            formattedEarningPower.uint256ToString(),
            1121
        );

        string[7] memory textParts = [
            textStyles,
            "<g>",
            textTokenId,
            textAccountType,
            textUnlockTimestamp,
            textEarningPower,
            "</g>"
        ];
        for (uint256 i = 0; i < textParts.length; i++) {
            svgSection = svgSection.concatenateString(textParts[i]);
        }
    }

    function _createCardTextLine(
        string memory _text,
        string memory _value,
        uint256 _yCoordinate
    ) internal pure returns (string memory svgSection) {
        uint256 xCoordinateStart = 60;
        uint256 xCoordinateEnd = 940;
        uint256 underlineOffset = 10;

        string memory textBox1 = string(
            abi.encodePacked(
                '<text x="',
                xCoordinateStart.uint256ToString(),
                '" y="',
                _yCoordinate.uint256ToString(),
                '" class="text">',
                _text,
                "</text>"
            )
        );
        string memory textBox2 = string(
            abi.encodePacked(
                '<text x="',
                xCoordinateEnd.uint256ToString(),
                '" y="',
                _yCoordinate.uint256ToString(),
                '" text-anchor="end" class="text">',
                _value,
                "</text>"
            )
        );
        string memory underline = _createTextUnderline(
            xCoordinateStart,
            xCoordinateEnd,
            _yCoordinate + underlineOffset
        );
        svgSection = textBox1.concatenateString(textBox2).concatenateString(underline);
    }

    function _createTextUnderline(
        uint256 _xCoordinateStart,
        uint256 _xCoordinateEnd,
        uint256 _yCoordinate
    ) internal pure returns (string memory svgSection) {
        string memory textUnderline = string(
            abi.encodePacked(
                '<path d="M',
                _xCoordinateStart.uint256ToString(),
                " ",
                _yCoordinate.uint256ToString(),
                " L",
                _xCoordinateEnd.uint256ToString(),
                " ",
                _yCoordinate.uint256ToString(),
                '" stroke="white" stroke-width="2" stroke-linecap="round"/>'
            )
        );
        svgSection = textUnderline;
    }
}
