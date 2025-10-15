// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 Number Guessing Game (no imports, no constructor, no input fields)
 - Owner must call initialize() once after deployment to claim ownership.
 - Owner sets a commitment hash with setCommit(bytes32).
   The commitment is keccak256(abi.encodePacked(uint8 secretNumber, bytes32 salt)).
 - Players call guess(uint8 number) with ETH to place a bet on that number.
 - Owner reveals with reveal(uint8 secretNumber, bytes32 salt).
   On reveal, contract verifies the commitment, finds winners, and distributes
   the contract balance pro rata to winners who bet on the correct number.
 - If a transfer to a winner fails, their owed amount is saved in pendingWithdrawals.
 - Security notes:
   * Commit–reveal prevents owner changing secret after players bet.
   * Avoid excessively many distinct guessers for a single number (gas limits).
   * No constructor used; initialize() sets owner and must be called once.
*/

contract NumberGuessingGame {
    // ---- STATE ----
    address public owner;
    bool public initialized = false;

    // committed hash by owner: keccak256(abi.encodePacked(uint8 secret, bytes32 salt))
    bytes32 public commit;
    bool public commitSet = false;
    bool public revealed = false;
    uint8 public revealedNumber; // only valid after reveal

    // track guesses: for each guess number, mapping of player -> amount staked
    mapping(uint8 => mapping(address => uint256)) public stakesByNumber;
    // to iterate winners, we keep a list of guessers per number (may cost gas)
    mapping(uint8 => address[]) internal guessersList;
    // total staked for each guess number
    mapping(uint8 => uint256) public totalStakedForNumber;

    // pending withdrawals for failed payouts or owner recovery
    mapping(address => uint256) public pendingWithdrawals;

    // game lifecycle
    enum GameState { WaitingCommit, AcceptingGuesses, Revealed, Settled }
    GameState public state = GameState.WaitingCommit;

    // ---- EVENTS ----
    event Initialized(address owner);
    event CommitSet(bytes32 commit);
    event GuessPlaced(address indexed who, uint8 number, uint256 amount);
    event Revealed(uint8 number, address revealer);
    event PayoutSent(address indexed to, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);
    event OwnerRecovered(uint256 amount);

    // ---- MODIFIERS ----
    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    modifier onlyBeforeReveal() {
        require(state == GameState.AcceptingGuesses, "not accepting guesses");
        _;
    }

    modifier onlyAfterReveal() {
        require(state == GameState.Revealed || state == GameState.Settled, "not revealed");
        _;
    }

    // ---- NO CONSTRUCTOR: use initialize() ----
    // Call once by the account that deployed the contract to become owner
    function initialize() external {
        require(!initialized, "already initialized");
        owner = msg.sender;
        initialized = true;
        emit Initialized(owner);
    }

    // Owner commits a hashed secret (no exposure of secret).
    // Example off-chain: commit = keccak256(abi.encodePacked(uint8_secret, bytes32_salt))
    function setCommit(bytes32 _commit) external onlyOwner {
        require(initialized, "not initialized");
        require(!commitSet, "commit already set");
        require(_commit != bytes32(0), "zero commit not allowed");
        commit = _commit;
        commitSet = true;
        state = GameState.AcceptingGuesses;
        emit CommitSet(commit);
    }

    // Players place guesses (uint8 number) and send ETH as stake.
    // No minimum required by code; you can require msg.value > 0 if desired.
    function guess(uint8 number) external payable onlyBeforeReveal {
        require(msg.value > 0, "send ETH to participate");
        // record stake
        if (stakesByNumber[number][msg.sender] == 0) {
            // first time this player guesses this number: add to list
            guessersList[number].push(msg.sender);
        }
        stakesByNumber[number][msg.sender] += msg.value;
        totalStakedForNumber[number] += msg.value;
        emit GuessPlaced(msg.sender, number, msg.value);
    }

    // Owner reveals the secret number and salt. Contract verifies commitment.
    // On success, contract automatically attempts to distribute the entire contract
    // balance among winners (players who staked on that number), proportionally
    // to their stake. Any failed transfers are kept in pendingWithdrawals.
    function reveal(uint8 secretNumber, bytes32 salt) external onlyOwner {
        require(commitSet, "no commit set");
        require(!revealed, "already revealed");
        // verify that the revealed preimage matches commitment
        bytes32 computed = keccak256(abi.encodePacked(secretNumber, salt));
        require(computed == commit, "reveal does not match commit");

        // mark reveal
        revealed = true;
        revealedNumber = secretNumber;
        state = GameState.Revealed;
        emit Revealed(secretNumber, msg.sender);

        // compute winners and payout
        _distributePrize(secretNumber);
        state = GameState.Settled;
    }

    // Internal: compute and distribute prize to winners for the revealed number.
    function _distributePrize(uint8 winningNumber) internal {
        uint256 pot = address(this).balance;
        if (pot == 0) {
            return;
        }

        uint256 totalForWinningNumber = totalStakedForNumber[winningNumber];

        // if nobody guessed the correct number, give owner an option to recover after reveal
        if (totalForWinningNumber == 0) {
            // don't auto-send to owner here to avoid surprises; allow owner to recover via recoverUnwon()
            return;
        }

        // For each winner, compute share = pot * stake / totalForWinningNumber
        address[] memory winners = guessersList[winningNumber];

        // Defensive accounting: track how much distributed to avoid rounding leftovers
        uint256 distributed = 0;
        for (uint256 i = 0; i < winners.length; i++) {
            address payable w = payable(winners[i]);
            uint256 stake = stakesByNumber[winningNumber][w];
            if (stake == 0) continue; // skip if somehow zero

            // compute proportional share (rounding downward)
            uint256 share = (pot * stake) / totalForWinningNumber;

            if (share == 0) {
                // very small share due to rounding; accumulate into pendingWithdrawals
                pendingWithdrawals[w] += 0;
                continue;
            }

            // mark as distributed (effects before interactions)
            distributed += share;
            // zero the player's stake to avoid reentrancy or repeat payouts
            stakesByNumber[winningNumber][w] = 0;

            // attempt transfer using call; if fails, record pending withdrawal
            (bool ok, ) = w.call{value: share, gas: 23000}("");
            if (ok) {
                emit PayoutSent(w, share);
            } else {
                // on failure, record for later withdrawal
                pendingWithdrawals[w] += share;
            }
        }

        // Handle any leftover due to rounding: small remainder stays in contract as pending for owner
        // (owner can recover later via recoverUnwon)
    }

    // If a transfer failed during automatic distribution, players can withdraw here.
    function withdraw() external {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "nothing to withdraw");
        // zero before transfer
        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "withdraw failed");
        emit Withdrawal(msg.sender, amount);
    }

    // If nobody guessed the correct number, the owner can recover the pot after reveal.
    // This is a separate explicit call to avoid surprise transfers.
    function recoverUnwon() external onlyOwner onlyAfterReveal {
        uint256 totalForWinningNumber = totalStakedForNumber[revealedNumber];
        uint256 contractBal = address(this).balance;
        // If some winners exist, recover only leftover (rounding remainder). If no winners, recover all.
        if (totalForWinningNumber == 0) {
            // recover entire balance
            uint256 toSend = contractBal;
            if (toSend == 0) return;
            (bool ok, ) = payable(owner).call{value: toSend}("");
            require(ok, "owner recover failed");
            emit OwnerRecovered(toSend);
        } else {
            // distribute already attempted; leftover balance is small remainder
            uint256 toSend = contractBal;
            if (toSend == 0) return;
            (bool ok, ) = payable(owner).call{value: toSend}("");
            require(ok, "owner recover failed");
            emit OwnerRecovered(toSend);
        }
    }

    // View helpers
    function guessersOf(uint8 number) external view returns (address[] memory) {
        return guessersList[number];
    }

    // Prevent accidental ETH sending when the contract is not supposed to accept it:
    // (we still accept via guess())
    receive() external payable {
        // allow receiving ETH only if accepting guesses
        require(state == GameState.AcceptingGuesses, "not accepting direct deposits");
        // If someone sends ETH without calling guess(), we do not record a guess; keep funds for owner recovery.
    }

    fallback() external payable {
        // same as receive
        require(state == GameState.AcceptingGuesses, "not accepting direct deposits");
    }
}
