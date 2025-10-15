**Number Guessing Game Smart Contract — Flow EVM**

**Contract Address:**  
0x7993587DaE3Cf6E37B68571eeAb2C8c43acA0456

***

**Overview**

This DApp is a simple, decentralized **Number Guessing Game** smart contract deployed on the Flow EVM. Players can guess a secret number on-chain for a chance to win an ETH prize. The contract features automated prize distribution upon a correct guess and owner controls for initialization and prize recovery.

***

**Features**

- **Automated Prize Payout:** Prize sent instantly to winner’s wallet on correct guess.
- **No External Imports or Constructors:** Lean, self-contained contract for seamless deployment.
- **Owner Controls:** Owner sets the secret number, prize, and may reclaim ETH if game ends without winner.
- **Transparent Gameplay:** All interactions recorded on-chain.

***

**How It Works**

- **Game Initialization**
  - Owner starts the game by calling `initGame(uint256 _secretNumber)` and sending ETH as the prize.
  - The game becomes active and awaits player guesses.

- **Player Guessing**
  - Any wallet may call `guess(uint256 _guess)` with their guess.
  - If the guessed number matches the secret, the contract:
    - Declares the caller as the winner.
    - Transfers the entire prize balance to the winner.
    - Ends the game.

- **Prize Recovery**  
  If nobody wins, owner can reclaim the unawarded ETH via `reclaimPrize()`.

- **Contract Balance**  
  Anyone can view the contract balance using `contractBalance()`.

***

**Usage Instructions**

1. **Initialize the Game (Owner Only)**
    - Call:
      ```solidity
      initGame{value: <prize in wei>}(SECRET_NUMBER)
      ```
    - Example:
      ```solidity
      initGame{value: 1000000000000000000}(42) // 1 ETH prize, secret number 42
      ```

2. **Submit a Guess (Anyone)**
    - Call:
      ```solidity
      guess(<your_guess>)
      ```
    - Example:
      ```solidity
      guess(42)
      ```

3. **Reclaim Prize (Owner Only)**
    - If the game is over and no winner, owner can call:
      ```solidity
      reclaimPrize()
      ```

4. **Check Contract Balance**
    - Call:
      ```solidity
      contractBalance()
      ```

***

**Requirements**

- **Flow EVM Wallet** (e.g., MetaMask, Flow-compatible wallet)
- **ETH** for gas and prize deposit

***

**License**

MIT

***

**Enjoy playing the Number Guessing Game on Flow EVM!**  


---

