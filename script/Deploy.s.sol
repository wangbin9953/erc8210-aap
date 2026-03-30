// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AAPCore} from "../src/AAPCore.sol";
import {MockERC8183} from "../src/MockERC8183.sol";

/// @notice Deploy AAPCore + MockERC8183 to Base Sepolia using USDC as settlement asset.
///
/// Usage:
///   forge script script/Deploy.s.sol:DeployScript \
///     --rpc-url base_sepolia \
///     --private-key $PRIVATE_KEY \
///     --broadcast \
///     --verify
///
/// Environment variables required:
///   PRIVATE_KEY   — deployer private key (hex, no 0x prefix)
///   RESOLVER_ADDR — address authorized to resolve Claims
///
/// Base Sepolia USDC: 0x036CbD53842c5426634e7929541eC2318f3dCF7e
contract DeployScript is Script {

    address constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address resolver    = vm.envAddress("RESOLVER_ADDR");
        address deployer    = vm.addr(deployerKey);

        console.log("Deployer:  ", deployer);
        console.log("Resolver:  ", resolver);
        console.log("USDC:      ", BASE_SEPOLIA_USDC);
        console.log("Chain ID:  ", block.chainid);

        vm.startBroadcast(deployerKey);

        // 1. Deploy mock ERC-8183 (for testnet — on mainnet this would be the real ERC-8183 contract)
        MockERC8183 mockJobs = new MockERC8183();
        console.log("MockERC8183 deployed at:", address(mockJobs));

        // 2. Deploy AAPCore
        AAPCore aap = new AAPCore(BASE_SEPOLIA_USDC, address(mockJobs), resolver);
        console.log("AAPCore deployed at:    ", address(aap));

        vm.stopBroadcast();

        // Print summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network:     Base Sepolia (chainId 84532)");
        console.log("MockERC8183:", address(mockJobs));
        console.log("AAPCore:    ", address(aap));
        console.log("USDC:       ", BASE_SEPOLIA_USDC);
        console.log("Resolver:   ", resolver);
    }
}
