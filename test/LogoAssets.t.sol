// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PngAsset} from "../src/PngAsset.sol";

interface VmAssets {
    function readFileBinary(string calldata path) external view returns (bytes memory);
}

/// @notice Offline checks for this logo assignment, not token/hook deployment tests.
/// @dev Reads the five delivered options and the delivered selected artifact.
///      No generated cache, pinned .imd inputs, network, vendor packages or FFI.
contract LogoAssetsTest {
    VmAssets private constant vm = VmAssets(address(uint160(uint256(keccak256("hevm cheat code")))));

    function test_MascotPng() public view {
        _check("logos/logo-1.png", 0xd031c31fb0f99d2d8ea89579caa9fded6f708c39cbf962a3778a0f56bdd99174);
    }

    function test_GeometricWalletPng() public view {
        _check("logos/logo-2.png", 0xea7ffdd2c33081cfa7f37eaedf0e78bf170bf902b0c5532dabf8ff85bbaf7998);
    }

    function test_LettermarkPng() public view {
        _check("logos/logo-3.png", 0xb3e962b2cd026f5615f12b0085e6f5331b25b7984333913b5182ce2b2ef39077);
    }

    function test_EmblemPng() public view {
        _check("logos/logo-4.png", 0x9e4f56383b26ba65118afc9fac500b94f50e8898c9e372f36ca1fe1ef835efe4);
    }

    function test_MemePng() public view {
        _check("logos/logo-5.png", 0x463afa0d060ba13cfd0c67bc3e3bb84d38d9c21e5cb4ccf15bf58a580cf40ced);
    }

    function test_SelectedArtifactEqualsGeometricOption() public view {
        bytes memory selected = vm.readFileBinary("artifacts/logo.png");
        bytes memory option = vm.readFileBinary("logos/logo-2.png");
        require(PngAsset.validPng(selected), "selected artifact is not an opaque 1024-square PNG");
        require(selected.length == option.length && keccak256(selected) == keccak256(option), "selected file differs");
    }

    function test_AllFiveOptionsDiffer() public view {
        string[5] memory paths =
            ["logos/logo-1.png", "logos/logo-2.png", "logos/logo-3.png", "logos/logo-4.png", "logos/logo-5.png"];
        bytes32[5] memory hashes;
        for (uint256 i; i < paths.length; ++i) {
            hashes[i] = keccak256(vm.readFileBinary(paths[i]));
            for (uint256 j; j < i; ++j) {
                require(hashes[i] != hashes[j], "two logo options have identical bytes");
            }
        }
    }

    function test_ValidatorRejectsBrokenSignature() public view {
        bytes memory png = vm.readFileBinary("logos/logo-2.png");
        png[0] = 0;
        require(!PngAsset.validPng(png), "accepted a file without PNG magic");
    }

    function test_ValidatorRejectsMissingImageData() public view {
        bytes memory png = vm.readFileBinary("logos/logo-2.png");
        // Keep only IHDR plus IEND: a correctly sized header is not a usable logo.
        bytes memory headerOnly = new bytes(45);
        for (uint256 i; i < 33; ++i) {
            headerOnly[i] = png[i];
        }
        for (uint256 i; i < 12; ++i) {
            headerOnly[33 + i] = png[png.length - 12 + i];
        }
        require(!PngAsset.validPng(headerOnly), "accepted a PNG without IDAT");
    }

    function test_ValidatorRejectsTruncatedFile() public view {
        bytes memory png = vm.readFileBinary("logos/logo-2.png");
        assembly ("memory-safe") {
            mstore(png, sub(mload(png), 12))
        }
        require(!PngAsset.validPng(png), "accepted a PNG without IEND");
    }

    function test_ValidatorRejectsAlphaChannel() public view {
        bytes memory png = vm.readFileBinary("logos/logo-2.png");
        png[25] = bytes1(uint8(6)); // RGBA; these deliverables must be opaque RGB.
        require(!PngAsset.validPng(png), "accepted an alpha-capable logo");
    }

    /// forge-config: default.fuzz.runs = 2000
    function testFuzz_HeaderRejectsIncorrectDimensions(uint32 width, uint32 height) public pure {
        // Valid 8-bit RGB IHDR except the two fuzzed dimensions.
        bytes memory header =
            abi.encodePacked(hex"89504e470d0a1a0a0000000d49484452", width, height, hex"0802000000", bytes4(0));
        require(PngAsset.validHeader(header) == (width == 1024 && height == 1024), "dimension acceptance differs");
    }

    function _check(string memory path, bytes32 digest) private view {
        bytes memory png = vm.readFileBinary(path);
        require(PngAsset.validPng(png), "not a complete, opaque 1024x1024 RGB PNG");
        // The digest covers every chunk and compressed pixel byte, not just IHDR.
        require(sha256(png) == digest, "reviewed image bytes were altered or corrupted");
    }
}
