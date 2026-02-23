install-noir:
	curl -L https://raw.githubusercontent.com/noir-lang/noirup/refs/heads/main/install | bash
	noirup --version 1.0.0-beta.16

install-barretenberg:
	curl -fsSL https://raw.githubusercontent.com/AztecProtocol/aztec-packages/refs/heads/next/barretenberg/bbup/install | bash
	bbup --version 3.0.0-nightly.20251104

install-starknet:
	curl --proto '=https' --tlsv1.2 -sSf https://sh.starkup.dev | sh

install-devnet:
	asdf plugin add starknet-devnet || true
	asdf install starknet-devnet 0.6.1

install-garaga:
	pip install garaga==1.0.1

install-app-deps:
	cd app && bun install

build-circuit:
	cd circuit && nargo build

exec-circuit:
	cd circuit && nargo execute witness

gen-vk:
	bb write_vk --scheme ultra_honk --oracle_hash keccak -b ./circuit/target/private_goverence.json -o ./circuit/target

# Use this if host `bb` fails with GLIBC/GLIBCXX version errors.
gen-vk-docker:
	docker run --rm \
		-v "$(PWD)":/work \
		-w /work \
		ubuntu:24.04 \
		bash -lc "apt-get update >/dev/null && apt-get install -y curl ca-certificates >/dev/null && \
		curl -fsSL https://raw.githubusercontent.com/AztecProtocol/aztec-packages/refs/heads/next/barretenberg/bbup/install | bash && \
		export PATH=\$$HOME/.bb:\$$PATH && \
		bbup --version 3.0.0-nightly.20251104 >/dev/null && \
		bb write_vk --scheme ultra_honk --oracle_hash keccak -b ./circuit/target/private_goverence.json -o ./circuit/target"

gen-verifier:
	cd contracts && garaga gen --system ultra_keccak_zk_honk --vk ../circuit/target/vk --project-name verifier

build-contracts:
	cd contracts && scarb build

start-devnet:
	starknet-devnet --accounts=2 --seed=0 --initial-balance=100000000000000000000000

accounts-file:
	curl -s -X POST -H "Content-Type: application/json" \
		--data '{"jsonrpc":"2.0","id":"1","method":"devnet_getPredeployedAccounts"}' http://127.0.0.1:5050/ \
		| jq '{"alpha-sepolia":{"devnet0":{"address":.result[0].address,"private_key":.result[0].private_key,"public_key":.result[0].public_key,"class_hash":"0xe2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6","deployed":true,"legacy":false,"salt":"0x14","type":"open_zeppelin"}}}' > ./contracts/accounts.json

declare-verifier:
	cd contracts && sncast \
		--accounts-file accounts.json \
		--account devnet0 \
		declare \
		--url http://127.0.0.1:5050/rpc \
		--package verifier \
		--contract-name UltraKeccakZKHonkVerifier

declare-main:
	cd contracts && sncast \
		--accounts-file accounts.json \
		--account devnet0 \
		declare \
		--url http://127.0.0.1:5050/rpc \
		--package main \
		--contract-name PrivateGoverence

copy-artifacts:
	cp ./circuit/target/private_goverence.json ./app/src/assets/circuit.json
	cp ./circuit/target/vk ./app/src/assets/vk.bin
	if [ -f ./contracts/target/release/main_PrivateGoverence.contract_class.json ]; then \
		cp ./contracts/target/release/main_PrivateGoverence.contract_class.json ./app/src/assets/main.json; \
	else \
		cp ./contracts/target/dev/main_PrivateGoverence.contract_class.json ./app/src/assets/main.json; \
	fi

run-app:
	cd app && bun run dev
