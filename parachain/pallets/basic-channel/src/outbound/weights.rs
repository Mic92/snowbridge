//! Autogenerated weights for basic_channel::outbound
//!
//! THIS FILE WAS AUTO-GENERATED USING THE SUBSTRATE BENCHMARK CLI VERSION 4.0.0-dev
//! DATE: 2021-11-25, STEPS: `50`, REPEAT: 20, LOW RANGE: `[]`, HIGH RANGE: `[]`
//! EXECUTION: Some(Wasm), WASM-EXECUTION: Compiled, CHAIN: Some("spec.json"), DB CACHE: 128

// Executed Command:
// target/release/snowbridge
// benchmark
// --chain
// spec.json
// --execution
// wasm
// --wasm-execution
// compiled
// --pallet
// basic_channel::outbound
// --extra
// --extrinsic
// *
// --repeat
// 20
// --steps
// 50
// --output
// pallets/basic-channel/src/outbound/weights.rs
// --template
// templates/module-weight-template.hbs


#![cfg_attr(rustfmt, rustfmt_skip)]
#![allow(unused_parens)]
#![allow(unused_imports)]

use frame_support::{traits::Get, weights::{Weight, constants::RocksDbWeight}};
use sp_std::marker::PhantomData;

/// Weight functions needed for basic_channel::outbound.
pub trait WeightInfo {
	fn on_commit_no_messages() -> Weight;
	fn on_commit(m: u32, p: u32, ) -> Weight;
}

/// Weights for basic_channel::outbound using the Snowbridge node and recommended hardware.
pub struct SnowbridgeWeight<T>(PhantomData<T>);
impl<T: frame_system::Config> WeightInfo for SnowbridgeWeight<T> {
	fn on_commit_no_messages() -> Weight {
		Weight::from_ref_time(5_228_000 as u64)
			.saturating_add(T::DbWeight::get().reads(2))
	}
	fn on_commit(m: u32, p: u32, ) -> Weight {
		Weight::from_ref_time(3_294_000 as u64)
			// Standard Error: 31_000
			.saturating_add(Weight::from_ref_time(100_849_000 as u64).saturating_mul(m as u64))
			// Standard Error: 1_000
			.saturating_add(Weight::from_ref_time(3_880_000 as u64).saturating_mul(p as u64))
			.saturating_add(T::DbWeight::get().reads(3 as u64))
			.saturating_add(T::DbWeight::get().writes(2 as u64))
	}
}

// For backwards compatibility and tests
impl WeightInfo for () {
	fn on_commit_no_messages() -> Weight {
		Weight::from_ref_time(5_228_000 as u64)
			.saturating_add(RocksDbWeight::get().reads(2))
	}
	fn on_commit(m: u32, p: u32, ) -> Weight {
		Weight::from_ref_time(0 as u64)
			// Standard Error: 31_000
			.saturating_add(Weight::from_ref_time(100_849_000 as u64).saturating_mul(m as u64))
			// Standard Error: 1_000
			.saturating_add(Weight::from_ref_time(3_880_000 as u64).saturating_mul(p as u64))
			.saturating_add(RocksDbWeight::get().reads(3 as u64))
			.saturating_add(RocksDbWeight::get().writes(2 as u64))
	}
}
