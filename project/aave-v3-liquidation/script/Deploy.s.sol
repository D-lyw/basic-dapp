// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from 'forge-std/Script.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';

contract DeployScript is Script {
    // 以太坊主网地址
    address constant MAINNET_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant MAINNET_AGGREGATION_ROUTER = 0x111111125421cA6dc452d289314280a0f8842A65; // 1inch V6
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Base 链地址
    address constant BASE_ADDRESS_PROVIDER = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
    address constant BASE_AGGREGATION_ROUTER = 0x111111125421cA6dc452d289314280a0f8842A65; // 1inch V6
    address constant BASE_WETH = 0x4200000000000000000000000000000000000006;

    // 默认 Builder 支付比例 60%
    uint256 constant DEFAULT_BUILDER_PAYMENT_PERCENTAGE = 60;

    function run() public {
        // 默认部署到主网
        // deployMainnet();

        deployBase();
    }

    function deployMainnet() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);

        new AaveV3FlashLoanSimple(
            MAINNET_ADDRESS_PROVIDER,
            MAINNET_AGGREGATION_ROUTER,
            MAINNET_WETH,
            DEFAULT_BUILDER_PAYMENT_PERCENTAGE
        );

        vm.stopBroadcast();
    }

    function deployBase() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);

        new AaveV3FlashLoanSimple(
            BASE_ADDRESS_PROVIDER,
            BASE_AGGREGATION_ROUTER,
            BASE_WETH,
            DEFAULT_BUILDER_PAYMENT_PERCENTAGE
        );

        vm.stopBroadcast();
    }
} 