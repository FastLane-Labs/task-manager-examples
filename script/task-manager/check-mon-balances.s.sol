// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckMonBalancesScript is Script {
    address[] private addresses = [
        0x516F6B4F2c38c3Ba4c7BA394b75f560Ec93adB4D,
        0x78B560DC0306ddF40C0Fd11773553e39791b86D6,
        0xFe113826fFA99DbbE7d57414ED74A50D0D887B2d,
        0xD20F0743367582D846284cc080c608f72b5E2DfD,
        0x651c01182f5aaC6fA9aa0bd5CFbaa79b8FA8a2f5
    ];

    function run() public view {
        uint8 decimals = 18; // Native MON uses 18 decimals
        string memory symbol = "MON";

        console.log("Checking native %s balances on Monad", symbol);
        console.log("Token decimals: %s", uint256(decimals));
        console.log("");
        console.log("Address Balances:");
        console.log("=================");

        for (uint256 i = 0; i < addresses.length; i++) {
            uint256 balance = addresses[i].balance;
            uint256 wholePart = balance / (10 ** decimals);
            uint256 fractionalPart = balance % (10 ** decimals);

            // Format the fractional part with proper decimals
            string memory fractionalStr = formatFractional(fractionalPart, decimals);

            console.log("%s: %s.%s MON", addresses[i], wholePart, fractionalStr);
        }
    }

    function formatFractional(uint256 fractional, uint8 decimals) internal pure returns (string memory) {
        // Convert fractional part to string with proper padding
        if (fractional == 0) return "0";

        // Calculate how many digits we need
        uint256 divisor = 10 ** decimals;
        string memory result = "";

        // Show up to 4 decimal places
        uint8 precision = 4;
        if (precision > decimals) precision = decimals;

        divisor = divisor / (10 ** precision);
        uint256 displayValue = fractional / divisor;

        // Convert to string
        result = vm.toString(displayValue);

        // Pad with leading zeros if necessary
        uint256 length = bytes(result).length;
        if (length < precision) {
            for (uint256 i = 0; i < precision - length; i++) {
                result = string(abi.encodePacked("0", result));
            }
        }

        // Remove trailing zeros
        bytes memory strBytes = bytes(result);
        uint256 end = strBytes.length;
        while (end > 1 && strBytes[end - 1] == "0") {
            end--;
        }

        bytes memory trimmed = new bytes(end);
        for (uint256 i = 0; i < end; i++) {
            trimmed[i] = strBytes[i];
        }

        return string(trimmed);
    }
}
