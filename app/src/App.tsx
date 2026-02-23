import { useEffect, useMemo, useState } from 'react'
import './App.css'
import { Noir } from '@noir-lang/noir_js'
import { DebugFileMap } from '@noir-lang/types'
import { UltraHonkBackend } from '@aztec/bb.js'
import { getZKHonkCallData, init, poseidonHashBN254 } from 'garaga'
import { Account, Contract, RpcProvider, WalletAccount, cairo } from 'starknet'
import { connect } from '@starknet-io/get-starknet'
import initNoirC from '@noir-lang/noirc_abi'
import initACVM from '@noir-lang/acvm_js'
import acvm from '@noir-lang/acvm_js/web/acvm_js_bg.wasm?url'
import noirc from '@noir-lang/noirc_abi/web/noirc_abi_wasm_bg.wasm?url'
import { flattenFieldsAsArray } from './helpers/proof'
import { ActionState } from './types'
import { bytecode, abi } from './assets/circuit.json'
import { abi as mainAbi } from './assets/main.json'
import vkUrl from './assets/vk.bin?url'

const RPC_URL = import.meta.env.VITE_STARKNET_RPC ?? 'http://127.0.0.1:5050/rpc'
const CONTRACT_ADDRESS = import.meta.env.VITE_GOVERNANCE_CONTRACT_ADDRESS ?? '0x0'

type Page = 'admin' | 'register' | 'vote' | 'results'
type SignerAccount = WalletAccount | Account

function App() {
  const [page, setPage] = useState<Page>('admin')
  const [status, setStatus] = useState<ActionState>(ActionState.Idle)
  const [error, setError] = useState<string>('')
  const [info, setInfo] = useState<string>('')
  const [vk, setVk] = useState<Uint8Array | null>(null)
  const [garagaReady, setGaragaReady] = useState(false)

  const [secretKey, setSecretKey] = useState('1')
  const [proposalId, setProposalId] = useState('1')
  const [voteOption, setVoteOption] = useState('0')

  const [adminProposalId, setAdminProposalId] = useState('1')
  const [optionsCount, setOptionsCount] = useState('2')
  const [registerSecret, setRegisterSecret] = useState('1')

  const [queryProposalId, setQueryProposalId] = useState('1')
  const [queryOptionId, setQueryOptionId] = useState('0')
  const [queryVotes, setQueryVotes] = useState<string>('0')

  useEffect(() => {
    const bootstrap = async () => {
      await init()
      await Promise.all([initACVM(fetch(acvm)), initNoirC(fetch(noirc))])
      const response = await fetch(vkUrl)
      const arrayBuffer = await response.arrayBuffer()
      setVk(new Uint8Array(arrayBuffer))
      setGaragaReady(true)
    }

    bootstrap().catch((e: unknown) => {
      setError(e instanceof Error ? e.message : String(e))
    })
  }, [])

  const provider = useMemo(() => new RpcProvider({ nodeUrl: RPC_URL }), [])

  const handleFailure = (e: unknown) => {
    setStatus(ActionState.Idle)
    setError(e instanceof Error ? e.message : String(e))
  }

  const connectAccount = async (): Promise<SignerAccount> => {
    setStatus(ActionState.ConnectingWallet)
    const wallet = await connect()
    if (!wallet) {
      throw new Error('Wallet connection rejected')
    }

    return WalletAccount.connect(provider, wallet)
  }

  const governanceContract = async (account: SignerAccount) => {
    if (CONTRACT_ADDRESS === '0x0') {
      throw new Error('Set VITE_GOVERNANCE_CONTRACT_ADDRESS in app/.env')
    }

    return new Contract({ abi: mainAbi, address: CONTRACT_ADDRESS, providerOrAccount: account })
  }

  const onCreateProposal = async () => {
    try {
      setError('')
      setInfo('')
      const account = await connectAccount()
      const contract = await governanceContract(account)

      setStatus(ActionState.SendingTransaction)
      const tx = await contract.create_proposal(Number(adminProposalId), Number(optionsCount))
      await provider.waitForTransaction(tx.transaction_hash)

      setStatus(ActionState.Complete)
      setInfo(`Created proposal ${adminProposalId}`)
    } catch (e) {
      handleFailure(e)
    }
  }

  const onRegisterCommitment = async () => {
    try {
      if (!garagaReady) {
        throw new Error('Garaga is still initializing. Please try again in a few seconds.')
      }

      setError('')
      setInfo('')
      const account = await connectAccount()
      const contract = await governanceContract(account)

      const secret = BigInt(registerSecret)
      const commitment = poseidonHashBN254(secret, secret)

      setStatus(ActionState.SendingTransaction)
      const tx = await contract.register_commitment(cairo.uint256(commitment))
      await provider.waitForTransaction(tx.transaction_hash)

      setStatus(ActionState.Complete)
      setInfo(`Wallet registered commitment ${commitment.toString()}`)
    } catch (e) {
      handleFailure(e)
    }
  }

  const onCastPrivateVote = async () => {
    try {
      if (!garagaReady) {
        throw new Error('Garaga is still initializing. Please try again in a few seconds.')
      }
      if (!vk || vk.length < 2) {
        throw new Error('Missing vk.bin: run setup and copy artifacts first')
      }

      setError('')
      setInfo('')
      setStatus(ActionState.Preparing)

      const secret = BigInt(secretKey)
      const pId = Number(proposalId)
      const option = Number(voteOption)

      const commitment = poseidonHashBN254(secret, secret)
      const nullifier = poseidonHashBN254(secret, BigInt(pId))

      const inputs = {
        secret_key: secret.toString(),
        proposal_id: pId,
        vote_option: option,
        commitment: commitment.toString(),
        nullifier: nullifier.toString(),
      }

      const noir = new Noir({ bytecode, abi: abi as never, debug_symbols: '', file_map: {} as DebugFileMap })
      const witness = await noir.execute(inputs)

      setStatus(ActionState.Proving)
      const honk = new UltraHonkBackend(bytecode, { threads: 1 })
      const proof = await honk.generateProof(witness.witness, { keccakZK: true })
      honk.destroy()

      setStatus(ActionState.PreparingCalldata)
      const callData = getZKHonkCallData(
        proof.proof,
        flattenFieldsAsArray(proof.publicInputs),
        vk,
      )

      const account = await connectAccount()
      const contract = await governanceContract(account)

      setStatus(ActionState.SendingTransaction)
      const tx = await contract.cast_private_vote(callData)
      await provider.waitForTransaction(tx.transaction_hash)

      setStatus(ActionState.Complete)
      setInfo(`Vote submitted. Nullifier: ${nullifier.toString()}`)
    } catch (e) {
      handleFailure(e)
    }
  }

  const onQueryVotes = async () => {
    try {
      setError('')
      const contract = new Contract({ abi: mainAbi, address: CONTRACT_ADDRESS, providerOrAccount: provider })
      const votes = await contract.get_option_votes(Number(queryProposalId), Number(queryOptionId))
      setQueryVotes(votes.toString())
    } catch (e) {
      handleFailure(e)
    }
  }

  return (
    <main className="layout">
      <section className="hero panel">
        <div>
          <h1>Private Governance</h1>
          <p className="sub">One commitment per wallet, one nullifier per proposal, anonymous vote proof in browser.</p>
        </div>
      </section>

      <nav className="tabs">
        <button className={page === 'admin' ? 'tab active' : 'tab'} onClick={() => setPage('admin')}>Admin</button>
        <button className={page === 'register' ? 'tab active' : 'tab'} onClick={() => setPage('register')}>Register</button>
        <button className={page === 'vote' ? 'tab active' : 'tab'} onClick={() => setPage('vote')}>Vote</button>
        <button className={page === 'results' ? 'tab active' : 'tab'} onClick={() => setPage('results')}>Results</button>
      </nav>

      {status !== ActionState.Idle && <p className="hint panel">{status}</p>}
      {info && <p className="ok panel">{info}</p>}
      {error && <p className="err panel">{error}</p>}

      {page === 'admin' && (
        <section className="panel">
          <h2>Create Proposal</h2>
          <p className="hint">Admin only. Existing proposal IDs cannot be reused.</p>
          <div className="grid">
            <label>Proposal ID<input value={adminProposalId} onChange={(e) => setAdminProposalId(e.target.value)} /></label>
            <label>Options Count<input value={optionsCount} onChange={(e) => setOptionsCount(e.target.value)} /></label>
          </div>
          <button onClick={onCreateProposal}>Create Proposal</button>
        </section>
      )}

      {page === 'register' && (
        <section className="panel">
          <h2>Register Commitment</h2>
          <p className="hint">Public registration. Each wallet can register only one commitment.</p>
          <div className="grid single">
            <label>Secret<input value={registerSecret} onChange={(e) => setRegisterSecret(e.target.value)} /></label>
          </div>
          <button onClick={onRegisterCommitment}>Register</button>
        </section>
      )}

      {page === 'vote' && (
        <section className="panel">
          <h2>Cast Private Vote</h2>
          <p className="hint">Generate proof in browser and submit on-chain.</p>
          <div className="grid">
            <label>Secret<input value={secretKey} onChange={(e) => setSecretKey(e.target.value)} /></label>
            <label>Proposal ID<input value={proposalId} onChange={(e) => setProposalId(e.target.value)} /></label>
            <label>Vote Option<input value={voteOption} onChange={(e) => setVoteOption(e.target.value)} /></label>
          </div>
          <button onClick={onCastPrivateVote}>Generate Proof and Vote</button>
        </section>
      )}

      {page === 'results' && (
        <section className="panel">
          <h2>Results</h2>
          <div className="grid">
            <label>Proposal ID<input value={queryProposalId} onChange={(e) => setQueryProposalId(e.target.value)} /></label>
            <label>Option ID<input value={queryOptionId} onChange={(e) => setQueryOptionId(e.target.value)} /></label>
          </div>
          <button onClick={onQueryVotes}>Get Votes</button>
          <p className="result">Votes: {queryVotes}</p>
        </section>
      )}
    </main>
  )
}

export default App
