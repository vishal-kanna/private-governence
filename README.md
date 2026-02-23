# private-goverence

Anonymous governance prototype for Starknet testnet/devnet using:
- Noir circuit for private vote proofs
- Barretenberg UltraHonk proof generation
- Garaga verifier calldata conversion
- Cairo contract with commitment registry + nullifier protection
- Bun + React frontend for admin and voting flows

## Folder structure

- `circuit`: Noir private voting circuit
- `contracts`: Cairo governance contract
- `app`: Bun frontend (proof generation + wallet interaction)

## Flow

1. Admin creates a proposal (`proposal_id`, `options_count`).
2. Voter wallet self-registers a commitment (`poseidon(secret, secret)`).
3. Voter generates a proof with public inputs:
   - `proposal_id`
   - `vote_option`
   - `commitment`
   - `nullifier = poseidon(secret, proposal_id)`
4. Contract verifies proof and checks:
   - commitment is registered
   - nullifier not used
   - option is valid
5. Vote tally increments while preserving voter anonymity.

Current anti-abuse model:
- one commitment per wallet at registration
- commitment must belong to caller when voting
- one vote per wallet per proposal
- one nullifier per proposal (prevents replay with same secret)

## Quick start

```bash
cd private-goverence
make install-app-deps
make build-circuit
make gen-vk
make gen-verifier
make build-contracts
make copy-artifacts
```

If `make gen-vk` fails with `GLIBC_*` or `GLIBCXX_*` errors from `bb`, run:

```bash
make gen-vk-docker
```

Start local chain:

```bash
make start-devnet
```

In another terminal:

```bash
cd private-goverence
make accounts-file
make declare-verifier
# then set VERIFIER_CLASSHASH in contracts/main/src/lib.cairo
make declare-main
# deploy with sncast deploy using the class hash from declare-main
```

Run app:

```bash
cd private-goverence/app
cp .env.example .env
bun run dev
```

## Environment

`app/.env.example`:

- `VITE_STARKNET_RPC`: Starknet RPC endpoint
- `VITE_GOVERNANCE_CONTRACT_ADDRESS`: deployed governance contract address

## Notes

- `circuit/Prover.toml` has a placeholder nullifier. Frontend computes correct values automatically.
- Replace `VERIFIER_CLASSHASH` in `contracts/main/src/lib.cairo` after declaring the generated verifier.
- For public testnet deployment, switch RPC/account profile in `contracts/snfoundry.toml` and app `.env`.
- If you changed contract logic, redeclare and redeploy `PrivateGoverence`, then update app `.env`.

## References used

- https://github.com/vitwit/cosmos-zk-gov
- https://thebojda.medium.com/how-i-built-an-anonymous-voting-system-on-the-ethereum-blockchain-using-zero-knowledge-proof-d5ab286228fd
- https://espejel.bearblog.dev/starknet-privacy-toolkit/
