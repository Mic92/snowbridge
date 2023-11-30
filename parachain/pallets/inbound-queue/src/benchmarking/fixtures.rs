use hex_literal::hex;
use snowbridge_beacon_primitives::CompactExecutionHeader;
use snowbridge_core::inbound::{Log, Message, Proof};
use sp_std::vec;

pub struct InboundQueueTest {
	pub execution_header: CompactExecutionHeader,
	pub message: Message,
}

pub fn make_create_message() -> InboundQueueTest {
	InboundQueueTest{
        execution_header: CompactExecutionHeader{
            parent_hash: hex!("8f69b84ec2fe39b299005cf30e855a2bcdd997dd1e5f79777271160015db6ae3").into(),
            block_number: 188,
            state_root: hex!("3f744f5e0322312fbcd6ea06e4e3db6cf8ff8a6258ee4f621df57165c3964806").into(),
            receipts_root: hex!("b4e733e6a4545303220f9954b9e895ecf31e5d6fe1557f27a0254a01132f38a7").into(),
        },
        message: Message {
            event_log: 	Log {
                address: hex!("eda338e4dc46038493b885327842fd3e301cab39").into(),
                topics: vec![
                    hex!("7153f9357c8ea496bba60bf82e67143e27b64462b49041f8e689e1b05728f84f").into(),
                    hex!("c173fac324158e77fb5840738a1a541f633cbec8884c6a601c567d2b376a0539").into(),
                    hex!("5f7060e971b0dc81e63f0aa41831091847d97c1a4693ac450cc128c7214e65e0").into(),
                ],
                data: hex!("00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002e000f000000000000000087d1f7fdfee7f651fabc8bfcb6e086c278b77a7d00e40b54020000000000000000000000000000000000000000000000000000000000").into(),
            },
            proof: Proof {
                block_hash: hex!("7ce27351fff56e7f0f28774766ad46dcf9c05e5cc5cf2c1914de08b34da3d0c9").into(),
                tx_index: 0,
                data: (vec![
                    hex!("b4e733e6a4545303220f9954b9e895ecf31e5d6fe1557f27a0254a01132f38a7").to_vec(),
                ], vec![
                    hex!("f9026d822080b9026702f9026301830150dfb9010000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000080000000000000000000000000000004000000000080000000000000000000000000000000000010100000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000040004000000000000002000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000200000000000010f90158f85894eda338e4dc46038493b885327842fd3e301cab39e1a0f78bb28d4b1d7da699e5c0bc2be29c2b04b5aab6aacf6298fe5304f9db9c6d7ea000000000000000000000000087d1f7fdfee7f651fabc8bfcb6e086c278b77a7df8fc94eda338e4dc46038493b885327842fd3e301cab39f863a07153f9357c8ea496bba60bf82e67143e27b64462b49041f8e689e1b05728f84fa0c173fac324158e77fb5840738a1a541f633cbec8884c6a601c567d2b376a0539a05f7060e971b0dc81e63f0aa41831091847d97c1a4693ac450cc128c7214e65e0b88000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000001e000f000000000000000087d1f7fdfee7f651fabc8bfcb6e086c278b77a7d0000").to_vec(),
                ]),
            },
        },
    }
}
