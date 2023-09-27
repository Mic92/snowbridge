// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2023 Snowfork <hello@snowfork.com>
#![cfg_attr(not(feature = "std"), no_std)]

use snowbridge_core::outbound::{Message, SubmitError};
use snowbridge_outbound_queue_merkle_tree::MerkleProof;
use xcm::prelude::MultiAssets;

sp_api::decl_runtime_apis! {
	pub trait OutboundQueueApi
	{
		fn prove_message(leaf_index: u64) -> Option<MerkleProof>;

		fn estimate_fee(message: &Message) -> Result<MultiAssets, SubmitError>;

		fn estimate_fee_by_command_index(command_index: u8) -> Result<MultiAssets, SubmitError>;
	}
}
