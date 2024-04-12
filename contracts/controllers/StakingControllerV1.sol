// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.25;

import "../interfaces/ParachainStaking.sol";
import "../wallets/StakingWallet.sol" as Wallet;
import "../common/errors.sol" as errors;

contract StakingControllerV1 {
    address public admin;
    address public wallet;

    mapping(address user => bool inWhitelist) public whitelist;
    address[] public usersInWhitelist;
    uint64 public usersCount;

    mapping(address user => uint256 stakedAmount) public activeStake;
    uint256 public activeStakeTotal;
    mapping(address user => TimedAmount[] timedAmounts) public pendingDeposits;
    uint256 public pendingDepositsTotal;
    uint256 public rewardPayoutDelay; // 2 rounds - https://docs.moonbeam.network/learn/features/staking/

    uint256 public notRewardBalance; // нужно, чтобы во время депозита юзера в claim не распределился депозит по юзерам

    mapping(address user => uint256 pended) public pendingUnbounds;
    uint256 public unboundStartRound;
    uint256 public unboundDelay; // 28 rounds - https://moonbeam.network/tutorial/stake-glmr/

    ParachainStaking public parachainStaking;
    address public collator; // Cryptor: 0x8730b791ee9fd8abf80caa654f4e4c5626ddbeee

    uint256 public latestClaimedRound;

    struct TimedAmount {
        uint256 amount;
        uint256 round;
    }

    event AdminChanged(address oldAdmin, address newAdmin);

    modifier OnlyAdmin() {
        if (msg.sender != admin) {
            revert errors.NotAdmin();
        }
        _;
    }

    modifier OnlyWhitelisted() {
        if (!whitelist[msg.sender]) {
            revert errors.NotInWhitelist();
        }
        _;
    }

    modifier OnlyNonZeroAddress(address adr) {
        if (adr == address(0)) {
            revert errors.ZeroAddress();
        }
        _;
    }

    modifier OnlyDiferentAddresses(address a1, address a2) {
        if (a1 == a2) {
            revert errors.SameAddress();
        }
        _;
    }

    modifier WhenCollatorSet() {
        if (collator == address(0)) {
            revert errors.CollatorNotSet();
        }
        _;
    }

    modifier WhenWalletSet() {
        if (wallet == address(0)) {
            revert errors.WalletNotSet();
        }
        _;
    }

    constructor(address stakingSystemContract_, address collator_, uint256 unboundDelay_) {
        admin = msg.sender;
        parachainStaking = ParachainStaking(stakingSystemContract_);
        collator = collator_;
        unboundDelay = unboundDelay_;
        rewardPayoutDelay = 2;
    }

    function setWallet(address newWallet) external OnlyAdmin {
        wallet = newWallet;
    }

    function setNewAdmin(
        address newAdmin
    ) external OnlyAdmin OnlyNonZeroAddress(newAdmin) OnlyDiferentAddresses(admin, newAdmin) {
        admin = newAdmin;
        emit AdminChanged(admin, newAdmin);
    }

    function addToWhitelist(address user) external OnlyAdmin OnlyNonZeroAddress(user) {
        if (!whitelist[user]) {
            revert errors.AlreadyInWhitelist();
        }
        whitelist[user] = true;
        usersInWhitelist.push(user);
        usersCount += 1;
    }

    function removeFromWhitelist(address user) external OnlyAdmin {
        if (!whitelist[user]) {
            revert errors.NotInWhitelist();
        }
        whitelist[user] = false;
        for (uint64 i = 0; i < usersCount; i++) {
            if (usersInWhitelist[i] == user) {
                usersInWhitelist[i] = usersInWhitelist[usersCount - 1];
                usersInWhitelist.pop();
                break;
            }
        }
        usersCount -= 1;
    }

    function setCollator(address newCollator) external OnlyAdmin {
        collator = newCollator;
    }

    function deposit() external payable OnlyWhitelisted WhenCollatorSet {
        address user = msg.sender;
        uint256 depositAmount = msg.value;
        if (depositAmount == 0) {
            revert errors.ZeroAmount();
        }
        notRewardBalance = depositAmount;
        claim();
        notRewardBalance = 0;
        if (true) {
            // todo: finish parachainStaking.delegate(collator, depositAmount, ???, ???)
        } else {
            parachainStaking.delegatorBondMore(collator, depositAmount);
        }
        _addToPendingDeposits(user, depositAmount);
    }

    function forceTransfer(address payable to, uint256 amount) external payable OnlyAdmin OnlyNonZeroAddress(to) {
        to.transfer(amount);
    }

    //    function forceUndelegate(uint256 amount) external OnlyAdmin {
    //         parachainStaking.delegatorBondMore(collator, );
    //         todo: finish
    //    }

    function updatePendingDeposits() public {
        uint256 currentRound = parachainStaking.round();
        if (pendingDepositsTotal > 0) {
            for (uint64 i = 0; i < usersCount; i++) {
                address user = usersInWhitelist[i];
                uint256 len = pendingDeposits[user].length;
                for (uint64 j = 0; j < len; j++) {
                    TimedAmount memory userPendingDeposit = pendingDeposits[user][j];
                    if (currentRound - userPendingDeposit.round > rewardPayoutDelay) {
                        activeStake[user] += userPendingDeposit.amount;
                        activeStakeTotal += userPendingDeposit.amount;
                        if (j != len - 1) {
                            pendingDeposits[user][j] = pendingDeposits[user][len - 1];
                        }
                        pendingDeposits[user].pop();
                        len -= 1;
                    }
                }
            }
        }
    }

    function claim() public OnlyWhitelisted {
        // todo:
        // + если delegationRequestIsPending == false, а pendingUnbounds > 0, то distributeUnbounded()
        // - считать две средних наград у юзера, у которого есть неактивный стейк
        //   с (currentRound - depositRound > rewardPayoutDelay)
        // - распределять награды только на те депозиты, у которых (currentRound - depositRound > rewardPayoutDelay)
        // - после исполнения метода обновлять activeStake, activeStakeTotal и pendingDepositsTotal

        if (!parachainStaking.delegationRequestIsPending(address(this), collator) && unboundStartRound != 0) {
            _distributeUnbounded();
        }

        uint256 currentRound = parachainStaking.round();

        updatePendingDeposits();

        uint256 totalRewards = getTotalRewards();
        uint256 averageRewardPerRound = totalRewards / (currentRound - 1 - latestClaimedRound);

        for (uint64 i = 0; i < usersCount; i++) {
            address payable user = payable(usersInWhitelist[i]);
            uint256 userActiveStake = activeStake[user];
            if (userActiveStake > 0) {
                uint256 rewardAmount = (totalRewards * userActiveStake) / activeStakeTotal;
                // todo: check cents distribution

                Wallet.StakingWallet(wallet).withdraw(user, rewardAmount);
            }
        }

        latestClaimedRound = currentRound - 1;
    }

    function getTotalRewards() public view returns (uint256) {
        return address(this).balance - notRewardBalance;
    }

    function startUnbound(uint256 unboundAmount) public OnlyWhitelisted {
        address user = msg.sender;
        if (pendingUnbounds[user] != 0) {
            revert errors.UnboundRequestExist();
        }
        // todo: rework with activeStake and
        // require(deposits[user].length > 0, "user has no deposits");
        // claim(), чтобы у юзеров был только 1 элемент в массиве deposits
        claim();
        // require(unboundAmount < deposits[user][0].amount, "unboundAmount is too big");

        uint64 len = 0;
        address[] memory usersWithPendingUnbound = new address[](usersCount);
        uint256[] memory usersUnbounds = new uint256[](usersCount);
        uint256 totalUnbound = unboundAmount;

        for (uint64 i = 0; i < usersCount; i++) {
            address userInWhitelist = usersInWhitelist[i];
            if (pendingUnbounds[userInWhitelist] > 0) {
                usersWithPendingUnbound[i] = userInWhitelist;
                usersUnbounds[i] = pendingUnbounds[userInWhitelist];
                totalUnbound += pendingUnbounds[userInWhitelist];
            }
        }

        uint256 currentRound = parachainStaking.round();

        if (len > 0) {
            parachainStaking.cancelDelegationRequest(collator);
        }

        parachainStaking.scheduleDelegatorBondLess(collator, totalUnbound);

        for (uint64 i = 0; i < len; i++) {
            address userWithUnbound = usersWithPendingUnbound[i];
            pendingUnbounds[userWithUnbound] = usersUnbounds[i];
        }
        pendingUnbounds[user] = unboundAmount;
        unboundStartRound = currentRound;
    }

    function cancelUnbound() public OnlyWhitelisted {
        claim();
        uint256 currentRound = parachainStaking.round();
        if (canFinishUnbound()) {
            // is too late, finishUnbound is need. todo: check this
            revert errors.Timeout();
        }

        address user = msg.sender;
        uint256 userPendingUnbound = pendingUnbounds[user];
        if (userPendingUnbound == 0) {
            revert errors.UnboundRequestNotExist();
        }

        uint64 len = 0;
        address[] memory usersWithPendingUnbound = new address[](usersCount);
        uint256[] memory usersUnbounds = new uint256[](usersCount);
        uint256 totalUnbound = 0;

        for (uint64 i = 0; i < usersCount; i++) {
            address userInWhitelist = usersInWhitelist[i];
            if (pendingUnbounds[userInWhitelist] > 0 && userInWhitelist != user) {
                usersWithPendingUnbound[i] = userInWhitelist;
                usersUnbounds[i] = pendingUnbounds[userInWhitelist];
                totalUnbound += pendingUnbounds[userInWhitelist];
            }
        }

        parachainStaking.cancelDelegationRequest(collator);

        if (totalUnbound > 0) {
            parachainStaking.scheduleDelegatorBondLess(collator, totalUnbound);
        }

        for (uint64 i = 0; i < len; i++) {
            pendingUnbounds[usersWithPendingUnbound[i]] = usersUnbounds[i];
        }
        unboundStartRound = currentRound;

        _addToPendingDeposits(user, userPendingUnbound);
    }

    function finishUnbound() public OnlyWhitelisted {
        _assertCanFinishUnbound();
        parachainStaking.executeDelegationRequest(address(this), collator);
        _distributeUnbounded();
    }

    function _distributeUnbounded() internal {
        for (uint64 i = 0; i < usersCount; i++) {
            address payable userInWhitelist = payable(usersInWhitelist[i]);
            if (pendingUnbounds[userInWhitelist] > 0) {
                userInWhitelist.transfer(pendingUnbounds[userInWhitelist]);
                pendingUnbounds[userInWhitelist] = 0;
            }
        }
        unboundStartRound = 0;
    }

    function _assertCanFinishUnbound() internal view {
        if (unboundStartRound == 0) {
            revert errors.UnboundRequestNotExist();
        }
        if (!canFinishUnbound()) {
            revert errors.TooEarly();
        }
    }

    function canFinishUnbound() public view returns (bool) {
        // example:
        // currentRound = 100
        // time to unbound = 28
        // can be finished on round = 100 + 28 + 1
        uint256 currentRound = parachainStaking.round();
        uint256 whenExecutable = unboundStartRound + unboundDelay;
        return currentRound > whenExecutable;
    }

    function _addToPendingDeposits(address user, uint256 amount) internal {
        // todo: finish
        uint256 currentRound = parachainStaking.round();
        pendingDeposits[user].push(TimedAmount({ amount: amount, round: currentRound }));
        pendingDepositsTotal += amount;
    }

    function getAllUsers() external view returns (address[] memory) {
        return usersInWhitelist;
    }
}
