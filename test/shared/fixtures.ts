import { ethers } from "hardhat";

import { ParachainStaking, StakingControllerV1, StakingWallet } from "../../types";
import { MOONBEAM_COLLATOR, MOONBEAM_UNBOUND_DELAY, STAKING_SYSTEM_CONTRACT } from "./constants";

export interface ContractsData {
  parachainStaking: ParachainStaking;
  stakingWallet: StakingWallet;
  stakingControllerV1: StakingControllerV1;
  collator: string;
  unboundDelay: number;
}

export async function deployStakingPool(): Promise<ContractsData> {
  // Contracts are deployed using the first signer/account by default
  const [owner, user1, user2] = await ethers.getSigners();
  
  const parachainStaking = await ethers.getContractAt("ParachainStaking", STAKING_SYSTEM_CONTRACT);

  const stakingWallet = await (await ethers.getContractFactory("StakingWallet")).deploy();
  const stakingWalletAddress = await stakingWallet.getAddress();

  const stakingControllerV1 = await (
    await ethers.getContractFactory("StakingControllerV1")
  ).deploy(stakingWalletAddress, MOONBEAM_COLLATOR, MOONBEAM_UNBOUND_DELAY);
  const stakingControllerV1Address = await stakingControllerV1.getAddress();
  
  await stakingWallet.setCaller(stakingControllerV1Address);
  
  return { parachainStaking, stakingWallet, stakingControllerV1, collator: MOONBEAM_COLLATOR, unboundDelay: MOONBEAM_UNBOUND_DELAY };
}
