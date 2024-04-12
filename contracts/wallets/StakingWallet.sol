// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.25;

import "../interfaces/ParachainStaking.sol" as Moonbeam;
import "../common/errors.sol" as errors;

contract StakingWallet {
    address public admin;
    address public caller;
    address public stakingSysContract;

    constructor() {
        admin = msg.sender;
    }

    modifier OnlyAdmin() {
        if (msg.sender != admin) {
            revert errors.NotAdmin();
        }
        _;
    }

    modifier OnlyCaller() {
        if (msg.sender != caller) {
            revert errors.NotAllowedToCall();
        }
        _;
    }

    modifier OnlyNonZeroAddress(address adr) {
        if (adr == address(0)) {
            revert errors.ZeroAddress();
        }
        _;
    }

    function setCaller(address newCaller) external OnlyAdmin OnlyNonZeroAddress(newCaller) {
        caller = newCaller;
    }

    function setStakingSysContract(address newStakingSysContract) external OnlyAdmin {
        stakingSysContract = newStakingSysContract;
    }

    function doStakingCall(bytes memory data) external payable OnlyCaller OnlyNonZeroAddress(stakingSysContract) {
        (bool success, bytes memory returnData) = stakingSysContract.call(data);
        if (!success) {
            revert errors.StakingSystemContractFailed();
        }
    }

    function transfer() external payable {}

    function withdraw(address payable recipient, uint256 amount) external OnlyCaller {
        recipient.transfer(amount);
    }
}
