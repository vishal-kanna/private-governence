use poseidon::poseidon::bn254::hash_2;

fn main(
    secret_key: Field,
    proposal_id: pub u32,
    vote_option: pub u8,
    commitment: pub Field,
    nullifier: pub Field,
) {
    // Restrict to two options: 0 or 1.
    assert(vote_option < 2);

    let expected_commitment = hash_2([secret_key, secret_key]);
    assert(expected_commitment == commitment);

    let expected_nullifier = hash_2([secret_key, proposal_id as Field]);
    assert(expected_nullifier == nullifier);
}
