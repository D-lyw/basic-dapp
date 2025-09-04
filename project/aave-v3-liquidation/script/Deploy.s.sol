// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console2} from 'forge-std/Script.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';
import {MultiVersionUniswapRouter} from '../src/MultiVersionUniswapRouter.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

contract DeployScript is Script {
    // 以太坊主网地址
    address constant MAINNET_AAVE_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant MAINNET_UNIVERSAL_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address constant MAINNET_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant MAINNET_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant MAINNET_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant MAINNET_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Base 链地址
    address constant BASE_AAVE_PROVIDER = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
    address constant BASE_UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant BASE_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant BASE_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address constant BASE_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant BASE_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant BASE_WETH = 0x4200000000000000000000000000000000000006;
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // 默认 Builder 支付比例 0%
    uint256 constant DEFAULT_BUILDER_PAYMENT_PERCENTAGE = 0;

    function run() public {
        // 默认部署到 Base 链
        deployBase();
        
        // 如果需要部署到主网，取消注释下面的行
        // deployMainnet();
    }

    function deployMainnet() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log('Deploying to Ethereum Mainnet...');
        console2.log('Deployer address:', deployer);
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. 首先部署 MultiVersionUniswapRouter
        MultiVersionUniswapRouter multiRouter = new MultiVersionUniswapRouter(
            MAINNET_UNIVERSAL_ROUTER,
            MAINNET_PERMIT2,
            MAINNET_V2_FACTORY,
            MAINNET_V3_FACTORY,
            MAINNET_POOL_MANAGER,
            MAINNET_WETH,
            MAINNET_USDC
        );
        
        console2.log('MultiVersionUniswapRouter deployed at:', address(multiRouter));

        // 2. 然后部署 AaveV3FlashLoanSimple
        AaveV3FlashLoanSimple flashLoan = new AaveV3FlashLoanSimple(
            MAINNET_AAVE_PROVIDER,
            address(multiRouter),
            MAINNET_WETH,
            DEFAULT_BUILDER_PAYMENT_PERCENTAGE
        );
        
        console2.log('AaveV3FlashLoanSimple deployed at:', address(flashLoan));
        console2.log('Owner:', flashLoan.owner());

        vm.stopBroadcast();
        
        console2.log('\n=== Mainnet Deployment Summary ===');
        console2.log('MultiVersionUniswapRouter:', address(multiRouter));
        console2.log('AaveV3FlashLoanSimple:', address(flashLoan));
        console2.log('Builder Payment Percentage:', DEFAULT_BUILDER_PAYMENT_PERCENTAGE, '%');
    }

    function deployBase() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log('Deploying to Base...');
        console2.log('Deployer address:', deployer);
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. 首先部署 MultiVersionUniswapRouter
        MultiVersionUniswapRouter multiRouter = new MultiVersionUniswapRouter(
            BASE_UNIVERSAL_ROUTER,
            BASE_PERMIT2,
            BASE_V2_FACTORY,
            BASE_V3_FACTORY,
            BASE_POOL_MANAGER,
            BASE_WETH,
            BASE_USDC
        );
        
        console2.log('MultiVersionUniswapRouter deployed at:', address(multiRouter));

        // 2. 然后部署 AaveV3FlashLoanSimple
        AaveV3FlashLoanSimple flashLoan = new AaveV3FlashLoanSimple(
            BASE_AAVE_PROVIDER,
            address(multiRouter),
            BASE_WETH,
            DEFAULT_BUILDER_PAYMENT_PERCENTAGE
        );
        
        console2.log('AaveV3FlashLoanSimple deployed at:', address(flashLoan));
        console2.log('Owner:', flashLoan.owner());

        vm.stopBroadcast();
        
        console2.log('\n=== Base Deployment Summary ===');
        console2.log('MultiVersionUniswapRouter:', address(multiRouter));
        console2.log('AaveV3FlashLoanSimple:', address(flashLoan));
        console2.log('Builder Payment Percentage:', DEFAULT_BUILDER_PAYMENT_PERCENTAGE, '%');
    }
}