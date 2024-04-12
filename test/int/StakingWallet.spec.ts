import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";

import { deployStakingPool } from "../shared/fixtures";
import { ethers } from "hardhat";

describe("Basic test", () => {
  it("test1", async () => {
    const { stakingWallet, stakingControllerV1, collator, unboundDelay } = await loadFixture(deployStakingPool);

    const stakingWalletAddress = await stakingWallet.getAddress();
    const [owner, user1, user2] = await ethers.getSigners();
    const balance = await owner.provider.getBalance("0x60b8349170dBe1B5Ae508D4B986171B5fb2070DF");
    console.log(`stakingWalletAddress: ${stakingWalletAddress}`);
    console.log(`balance: ${balance}`);
    // expect(price).to.be.closeTo(intendedPrice, intendedPrice.div(10000));
  });
});
