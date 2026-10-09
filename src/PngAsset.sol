// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Structural validation for the delivered static, opaque 1024-square RGB logos.
/// @dev Not a general PNG decoder. File fingerprints in the tests authenticate all
///      bytes; logos/verify.py additionally checks CRCs and decompresses the raster.
library PngAsset {
    function validHeader(bytes memory png) internal pure returns (bool) {
        if (png.length < 33) return false;
        return _u32(png, 0) == 0x89504e47 && _u32(png, 4) == 0x0d0a1a0a && _u32(png, 8) == 13
            && _u32(png, 12) == 0x49484452 && _u32(png, 16) == 1024 && _u32(png, 20) == 1024 && png[24] == 0x08
            && png[25] == 0x02 && png[26] == 0 && png[27] == 0 && png[28] == 0;
    }

    function validPng(bytes memory png) internal pure returns (bool) {
        if (!validHeader(png)) return false;
        uint256 offset = 33;
        uint256 imageBytes = 0;
        while (offset + 12 <= png.length) {
            uint256 size = _u32(png, offset);
            uint32 kind = _u32(png, offset + 4);
            if (size > png.length - offset - 12) return false;
            // Reject tRNS transparency, a second IHDR, and APNG's acTL control chunk.
            if (kind == 0x74524e53 || kind == 0x49484452 || kind == 0x6163544c) return false;
            if (kind == 0x49444154) imageBytes += size;
            if (kind == 0x49454e44) return size == 0 && offset + 12 == png.length && imageBytes > 0;
            offset += size + 12;
        }
        return false;
    }

    function _u32(bytes memory data, uint256 offset) private pure returns (uint32 value) {
        assembly ("memory-safe") {
            value := shr(224, mload(add(add(data, 32), offset)))
        }
    }
}
