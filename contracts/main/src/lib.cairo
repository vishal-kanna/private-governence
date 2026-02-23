use starknet::ContractAddress;

#[starknet::interface]
trait IPrivateGoverence<TContractState> {
    fn create_proposal(ref self: TContractState, proposal_id: u32, options_count: u8);
    fn register_commitment(ref self: TContractState, commitment: u256);
    fn cast_private_vote(ref self: TContractState, full_proof_with_hints: Span<felt252>);
    fn get_option_votes(self: @TContractState, proposal_id: u32, option_id: u8) -> u64;
    fn is_nullifier_used(self: @TContractState, nullifier: u256) -> bool;
    fn is_commitment_registered(self: @TContractState, commitment: u256) -> bool;
    fn is_wallet_registered(self: @TContractState, wallet: ContractAddress) -> bool;
}

#[starknet::contract]
mod PrivateGoverence {
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map,
    };
    use starknet::syscalls;
    use starknet::{ContractAddress, get_caller_address, SyscallResultTrait};

    // Replace after `make declare-verifier`
    const VERIFIER_CLASSHASH: felt252 = 0x2612b29cb541a5c5f126a90f1c133b9e0821b5eb527b744e36d4d8374b92801;

    #[storage]
    struct Storage {
        admin: ContractAddress,
        proposal_exists: Map<u32, bool>,
        proposal_options_count: Map<u32, u8>,
        votes: Map<u32, Map<u8, u64>>,
        commitments: Map<u256, bool>,
        commitment_owner: Map<u256, ContractAddress>,
        wallet_registered: Map<ContractAddress, bool>,
        nullifiers: Map<u256, bool>,
        wallet_voted_in_proposal: Map<u32, Map<ContractAddress, bool>>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ProposalCreated: ProposalCreated,
        CommitmentRegistered: CommitmentRegistered,
        VoteCast: VoteCast,
    }

    #[derive(Drop, starknet::Event)]
    struct ProposalCreated {
        proposal_id: u32,
        options_count: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct CommitmentRegistered {
        commitment: u256,
        wallet: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct VoteCast {
        proposal_id: u32,
        option_id: u8,
        nullifier: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
    }

    fn only_admin(self: @ContractState) {
        let caller = get_caller_address();
        assert(caller == self.admin.read(), 'Only admin');
    }

    fn u256_to_u32(value: u256) -> u32 {
        assert(value.high == 0, 'u32 conversion high != 0');
        assert(value.low <= 4294967295_u128, 'u32 conversion overflow');
        value.low.try_into().unwrap()
    }

    fn u256_to_u8(value: u256) -> u8 {
        assert(value.high == 0, 'u8 conversion high != 0');
        assert(value.low <= 255_u128, 'u8 conversion overflow');
        value.low.try_into().unwrap()
    }

    #[abi(embed_v0)]
    impl IPrivateGoverenceImpl of super::IPrivateGoverence<ContractState> {
        fn create_proposal(ref self: ContractState, proposal_id: u32, options_count: u8) {
            only_admin(@self);
            assert(options_count > 1, 'Need at least 2 options');
            assert(self.proposal_exists.entry(proposal_id).read() == false, 'Proposal exists');

            self.proposal_exists.entry(proposal_id).write(true);
            self.proposal_options_count.entry(proposal_id).write(options_count);
            self.emit(Event::ProposalCreated(ProposalCreated { proposal_id, options_count }));
        }

        fn register_commitment(ref self: ContractState, commitment: u256) {
            let wallet = get_caller_address();
            assert(self.commitments.entry(commitment).read() == false, 'Commitment exists');
            assert(self.wallet_registered.entry(wallet).read() == false, 'Wallet already registered');

            self.commitments.entry(commitment).write(true);
            self.commitment_owner.entry(commitment).write(wallet);
            self.wallet_registered.entry(wallet).write(true);
            self.emit(Event::CommitmentRegistered(CommitmentRegistered { commitment, wallet }));
        }

        fn cast_private_vote(ref self: ContractState, full_proof_with_hints: Span<felt252>) {
            let mut res = syscalls::library_call_syscall(
                VERIFIER_CLASSHASH.try_into().unwrap(),
                selector!("verify_ultra_keccak_zk_honk_proof"),
                full_proof_with_hints,
            )
                .unwrap_syscall();

            let public_inputs = Serde::<Option<Span<u256>>>::deserialize(ref res)
                .unwrap()
                .expect('Invalid proof');

            // Noir circuit public inputs order:
            // proposal_id, vote_option, commitment, nullifier
            let proposal_id = u256_to_u32(*public_inputs[0]);
            let option_id = u256_to_u8(*public_inputs[1]);
            let commitment = *public_inputs[2];
            let nullifier = *public_inputs[3];

            assert(self.proposal_exists.entry(proposal_id).read(), 'Unknown proposal');
            let options_count = self.proposal_options_count.entry(proposal_id).read();
            assert(option_id < options_count, 'Invalid option');

            assert(self.commitments.entry(commitment).read(), 'Commitment not registered');
            let caller = get_caller_address();
            let owner = self.commitment_owner.entry(commitment).read();
            assert(owner == caller, 'Commitment owner mismatch');
            assert(
                self.wallet_voted_in_proposal.entry(proposal_id).entry(caller).read() == false,
                'Wallet already voted',
            );
            assert(self.nullifiers.entry(nullifier).read() == false, 'Nullifier already used');

            self.nullifiers.entry(nullifier).write(true);
            self.wallet_voted_in_proposal.entry(proposal_id).entry(caller).write(true);

            let current_votes = self.votes.entry(proposal_id).entry(option_id).read();
            self.votes.entry(proposal_id).entry(option_id).write(current_votes + 1);

            self.emit(Event::VoteCast(VoteCast { proposal_id, option_id, nullifier }));
        }

        fn get_option_votes(self: @ContractState, proposal_id: u32, option_id: u8) -> u64 {
            self.votes.entry(proposal_id).entry(option_id).read()
        }

        fn is_nullifier_used(self: @ContractState, nullifier: u256) -> bool {
            self.nullifiers.entry(nullifier).read()
        }

        fn is_commitment_registered(self: @ContractState, commitment: u256) -> bool {
            self.commitments.entry(commitment).read()
        }

        fn is_wallet_registered(self: @ContractState, wallet: ContractAddress) -> bool {
            self.wallet_registered.entry(wallet).read()
        }
    }
}
