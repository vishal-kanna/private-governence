export enum ActionState {
  Idle = 'Idle',
  Preparing = 'Preparing witness',
  Proving = 'Generating proof',
  PreparingCalldata = 'Preparing calldata',
  ConnectingWallet = 'Connecting wallet',
  SendingTransaction = 'Sending transaction',
  Complete = 'Complete',
}
