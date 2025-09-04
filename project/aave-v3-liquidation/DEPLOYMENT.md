# 部署指南

## 概述

本项目包含两个主要合约：
- `AaveV3FlashLoanSimple.sol` - Aave V3 闪电贷清算合约
- `MultiVersionUniswapRouter.sol` - 多版本 Uniswap 路由器

## 支持的网络

### 以太坊主网 (Mainnet)
- Aave V3 Pool Address Provider: `0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e`
- Uniswap Universal Router: `0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af`
- WETH: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`
- USDC: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`

### Base 网络
- Aave V3 Pool Address Provider: `0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D`
- Uniswap Universal Router: `0x6fF5693b99212Da76ad316178A184AB56D299b43`
- WETH: `0x4200000000000000000000000000000000000006`
- USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

## 部署步骤

### 1. 环境准备

确保你的 `.env` 文件包含以下变量：
```bash
PRIVATE_KEY=your_private_key_here
ETHERSCAN_API_KEY=your_etherscan_api_key
BASESCAN_API_KEY=your_basescan_api_key
```

### 2. 编译合约

```bash
forge build
```

### 3. 运行测试

```bash
forge test
```

### 4. 部署到 Base 网络（默认）

```bash
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $BASESCAN_API_KEY
```

### 5. 部署到以太坊主网

修改 `script/Deploy.s.sol` 中的 `run()` 函数，取消注释主网部署：

```solidity
function run() public {
    deployMainnet(); // 取消注释这行
    // deployBase(); // 注释这行
}
```

然后运行：

```bash
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

## 部署后验证

部署完成后，脚本会输出：
- MultiVersionUniswapRouter 合约地址
- AaveV3FlashLoanSimple 合约地址
- 合约所有者地址
- Builder 支付百分比配置

## 注意事项

1. **私钥安全**：确保私钥安全，不要在公共代码库中暴露
2. **Gas 费用**：部署前检查当前网络的 Gas 价格
3. **合约验证**：部署后确保合约在区块链浏览器上正确验证
4. **权限管理**：部署者将成为合约的所有者，拥有管理权限

## 合约功能

### AaveV3FlashLoanSimple
- 执行 Aave V3 闪电贷清算
- 支持多种代币交换路径
- 可暂停/恢复功能
- Builder 费用分成机制

### MultiVersionUniswapRouter
- 支持 Uniswap V2、V3、V4 协议
- 智能路径选择
- 流动性优化
- 滑点保护

## 故障排除

如果遇到部署问题：
1. 检查网络连接和 RPC URL
2. 确认私钥和 API 密钥正确
3. 验证合约地址是否为最新版本
4. 查看 Gas 限制设置