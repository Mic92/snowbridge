// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2023 Snowfork <hello@snowfork.com>
pragma solidity 0.8.20;

import {ScaleCodec} from "./utils/ScaleCodec.sol";
import {ParaID} from "./Types.sol";

/**
 * @title SCALE encoders for common Substrate types
 */
library SubstrateTypes {
    error UnsupportedCompactEncoding();

    /**
     * @dev Encodes `MultiAddress::Id`: https://crates.parity.io/sp_runtime/enum.MultiAddress.html#variant.Id
     * @return bytes SCALE-encoded bytes
     */
    // solhint-disable-next-line func-name-mixedcase
    function MultiAddressWithID(bytes32 account) internal pure returns (bytes memory) {
        return bytes.concat(hex"00", account);
    }

    /**
     * @dev Encodes `H160`: https://crates.parity.io/sp_core/struct.H160.html
     * @return bytes SCALE-encoded bytes
     */
    // solhint-disable-next-line func-name-mixedcase
    function H160(address account) internal pure returns (bytes memory) {
        return abi.encodePacked(account);
    }

    function VecU8(bytes memory input) internal pure returns (bytes memory) {
        return bytes.concat(ScaleCodec.checkedEncodeCompactU32(input.length), input);
    }

    /**
     * @dev Encodes `Option::None`: https://doc.rust-lang.org/std/option/enum.Option.html#variant.None
     * @return bytes SCALE-encoded bytes
     */
    // solhint-disable-next-line func-name-mixedcase
    function None() internal pure returns (bytes memory) {
        return hex"00";
    }

    // solhint-disable-next-line func-name-mixedcase
    function OptionParaID(ParaID v) internal pure returns (bytes memory) {
        if (ParaID.unwrap(v) == 0) {
            return hex"00";
        } else {
            return bytes.concat(bytes1(0x01), ScaleCodec.encodeU32(uint32(ParaID.unwrap(v))));
        }
    }

    /**
     * @dev SCALE-encodes `router_primitives::inbound::VersionedMessage` containing payload
     * `NativeTokensMessage::Create`
     */
    // solhint-disable-next-line func-name-mixedcase
    function RegisterToken(address gateway, address token, bytes2 createCallIndex, uint256 extraFee)
        internal
        view
        returns (bytes memory)
    {
        return bytes.concat(
            bytes1(0x00),
            ScaleCodec.encodeU64(uint64(block.chainid)),
            ScaleCodec.encodeU128(uint128(extraFee)),
            bytes1(0x00),
            SubstrateTypes.H160(gateway),
            SubstrateTypes.H160(token),
            createCallIndex
        );
    }

    /**
     * @dev SCALE-encodes `router_primitives::inbound::VersionedMessage` containing payload
     * `NativeTokensMessage::Mint`
     */
    // solhint-disable-next-line func-name-mixedcase
    function SendToken(address gateway, address token, bytes32 recipient, uint128 amount, uint256 extraFee)
        internal
        view
        returns (bytes memory)
    {
        return bytes.concat(
            bytes1(0x00),
            ScaleCodec.encodeU64(uint64(block.chainid)),
            ScaleCodec.encodeU128(uint128(extraFee)),
            bytes1(0x01),
            SubstrateTypes.H160(gateway),
            SubstrateTypes.H160(token),
            bytes1(0x00),
            recipient,
            ScaleCodec.encodeU128(amount)
        );
    }

    function SendToken(
        address gateway,
        address token,
        ParaID paraID,
        bytes32 recipient,
        uint128 amount,
        uint256 extraFee
    ) internal view returns (bytes memory) {
        return bytes.concat(
            bytes1(0x00),
            ScaleCodec.encodeU64(uint64(block.chainid)),
            ScaleCodec.encodeU128(uint128(extraFee)),
            bytes1(0x01),
            SubstrateTypes.H160(gateway),
            SubstrateTypes.H160(token),
            bytes1(0x01),
            ScaleCodec.encodeU32(uint32(ParaID.unwrap(paraID))),
            recipient,
            ScaleCodec.encodeU128(amount)
        );
    }

    function SendToken(
        address gateway,
        address token,
        ParaID paraID,
        address recipient,
        uint128 amount,
        uint256 extraFee
    ) internal view returns (bytes memory) {
        return bytes.concat(
            bytes1(0x00),
            ScaleCodec.encodeU64(uint64(block.chainid)),
            ScaleCodec.encodeU128(uint128(extraFee)),
            bytes1(0x01),
            SubstrateTypes.H160(gateway),
            SubstrateTypes.H160(token),
            bytes1(0x02),
            ScaleCodec.encodeU32(uint32(ParaID.unwrap(paraID))),
            abi.encodePacked(recipient),
            ScaleCodec.encodeU128(amount)
        );
    }

    /**
     * @dev SCALE-encodes `router_primitives::inbound::VersionedMessage` containing payload
     * for arbitrary transact
     */
    // solhint-disable-next-line func-name-mixedcase
    function Transact(address gateway, bytes calldata payload, uint256 extraFee, uint64 refTime, uint64 proofSize)
        internal
        view
        returns (bytes memory)
    {
        return bytes.concat(
            bytes1(0x00),
            ScaleCodec.encodeU64(uint64(block.chainid)),
            ScaleCodec.encodeU128(uint128(extraFee)),
            bytes1(0x02),
            SubstrateTypes.H160(gateway),
            ScaleCodec.checkedEncodeCompactU32(payload.length),
            payload,
            ScaleCodec.encodeU64(refTime),
            ScaleCodec.encodeU64(proofSize)
        );
    }
}
