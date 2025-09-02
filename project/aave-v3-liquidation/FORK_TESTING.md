# Mainnet Fork Testing Guide

本指南将帮助您使用 mainnet fork 来测试 AaveV3FlashLoanSimple 合约。

## 📋 目录

- [概述](#概述)
- [环境设置](#环境设置)
- [测试文件说明](#测试文件说明)
- [运行测试](#运行测试)
- [测试用例详解](#测试用例详解)
- [故障排除](#故障排除)
- [最佳实践](#最佳实践)

## 🎯 概述

Mainnet fork 测试允许我们在本地环境中使用真实的以太坊主网数据来测试合约，这样可以：

- 使用真实的 Aave V3 协议合约
- 访问真实的价格数据
- 测试与真实 DeFi 协议的交互
- 验证清算逻辑的正确性

## ⚙️ 环境设置

### 1. 获取 RPC 端点

您需要一个以太坊主网的 RPC 端点。推荐的提供商：

- **Alchemy** (推荐): https://www.alchemy.com/
- **Infura**: https://infura.io/
- **Ankr**: https://www.ankr.com/
- **QuickNode**: https://www.quicknode.com/

### 2. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑 .env 文件，添加您的 RPC URL
vim .env
```

在 `.env` 文件中设置：

```bash
MAINNET_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/YOUR_API_KEY
ALCHEMY_API_KEY=YOUR_API_KEY
FORK_BLOCK_NUMBER=18500000
```

### 3. 安装依赖

确保您已经安装了 Foundry：

```bash
# 安装 Foundry (如果尚未安装)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 安装项目依赖
forge install
```

## 📁 测试文件说明

### 主要文件

- `test/AaveV3FlashLoanSimple.fork.t.sol` - 主要的 fork 测试文件
- `foundry.toml` - Foundry 配置文件（包含 fork 配置）
- `test-fork.sh` - 测试运行脚本
- `.env.example` - 环境变量模板

### 测试合约结构

```solidity
contract AaveV3FlashLoanSimpleForkTest is Test {
    // 真实的主网地址
    address constant AAVE_POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant UNIVERSAL_ROUTER = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;
    // ... 其他地址
    
    // 测试用例
    function test_DeploymentOnFork() public { ... }
    function test_GetUserAccountData() public { ... }
    // ... 其他测试
}
```

## 🚀 运行测试

### 方法 1: 使用测试脚本（推荐）

```bash
# 运行交互式测试脚本
./test-fork.sh
```

脚本提供以下选项：
1. 运行所有 fork 测试
2. 运行部署测试
3. 运行用户账户数据测试
4. 运行价格预言机测试
5. 运行代币信息测试
6. 运行清算预检测试
7. 运行闪电贷可用性测试
8. 运行访问控制测试
9. 运行紧急提取测试

### 方法 2: 直接使用 Forge 命令

```bash
# 运行所有 fork 测试
forge test --match-path "*fork*" --fork-url $MAINNET_RPC_URL -vvv

# 运行特定测试
forge test --match-test test_DeploymentOnFork --fork-url $MAINNET_RPC_URL -vvv

# 使用特定区块号
forge test --match-path "*fork*" --fork-url $MAINNET_RPC_URL --fork-block-number 18500000 -vvv
```

### 方法 3: 使用配置文件

```bash
# 使用 fork profile
forge test --profile fork --match-path "*fork*" -vvv
```

## 🧪 测试用例详解

### 1. 部署测试 (`test_DeploymentOnFork`)

验证合约在 fork 环境中的正确部署：

```solidity
function test_DeploymentOnFork() public {
    assertEq(address(liquidation.ADDRESSES_PROVIDER()), AAVE_POOL_ADDRESSES_PROVIDER);
    assertEq(address(liquidation.UNIVERSAL_ROUTER()), UNIVERSAL_ROUTER);
    // ... 其他断言
}
```

### 2. 用户账户数据测试 (`test_GetUserAccountData`)

获取并验证真实用户的账户数据：

```solidity
function test_GetUserAccountData() public {
    (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        // ... 其他数据
    ) = pool.getUserAccountData(testUser);
    
    console2.log("Total collateral:", totalCollateralBase);
    console2.log("Total debt:", totalDebtBase);
}
```

### 3. 价格预言机测试 (`test_PriceOracle`)

验证 Aave 价格预言机的功能：

```solidity
function test_PriceOracle() public {
    uint256 wethPrice = oracle.getAssetPrice(WETH);
    uint256 usdcPrice = oracle.getAssetPrice(USDC);
    
    assertGt(wethPrice, 0, "WETH price should be greater than 0");
    assertGt(usdcPrice, 0, "USDC price should be greater than 0");
}
```

### 4. 清算预检测试 (`test_LiquidationPrecheck`)

检查用户的清算条件：

```solidity
function test_LiquidationPrecheck() public {
    (, uint256 totalDebtBase, , , , uint256 healthFactor) = pool.getUserAccountData(testUser);
    
    if (healthFactor < 1e18) {
        console2.log("User is eligible for liquidation");
        // 检查具体的债务和抵押品
    }
}
```

### 5. 闪电贷可用性测试 (`test_FlashLoanAvailability`)

验证各种资产的闪电贷流动性：

```solidity
function test_FlashLoanAvailability() public {
    address[] memory assets = new address[](3);
    assets[0] = WETH;
    assets[1] = USDC;
    assets[2] = WBTC;
    
    for (uint i = 0; i < assets.length; i++) {
        // 检查可用流动性
    }
}
```

## 🔧 故障排除

### 常见问题

#### 1. RPC 连接失败

```
Error: Failed to get chain ID
```

**解决方案：**
- 检查 RPC URL 是否正确
- 确认 API 密钥有效
- 尝试不同的 RPC 提供商

#### 2. 区块号过旧

```
Error: Block number too old
```

**解决方案：**
- 更新 `FORK_BLOCK_NUMBER` 到更近的区块
- 使用最新区块（不设置区块号）

#### 3. 测试用户没有债务

```
User has no debt in this asset
```

**解决方案：**
- 在 `_findUserWithDebt()` 函数中添加真实的有债务用户地址
- 使用 Aave 协议的公开数据找到合适的测试用户

#### 4. Gas 限制问题

```
Error: Transaction ran out of gas
```

**解决方案：**
- 在 `foundry.toml` 中增加 gas 限制：

```toml
[profile.fork]
gas_limit = 30000000
```

### 调试技巧

1. **增加详细输出：**
   ```bash
   forge test --match-test test_name -vvvv
   ```

2. **使用控制台日志：**
   ```solidity
   console2.log("Debug info:", value);
   ```

3. **检查特定区块状态：**
   ```bash
   forge test --fork-block-number 18500000 -vvv
   ```

## 💡 最佳实践

### 1. 选择合适的区块号

- 使用相对较新的区块（1-7天内）
- 避免使用过于久远的区块
- 考虑重要事件发生的区块（如协议升级）

### 2. 管理测试数据

```solidity
// 使用真实但匿名的地址
address constant TEST_USER_1 = 0x1234...;
address constant TEST_USER_2 = 0x5678...;

// 记录测试时的重要信息
struct TestSnapshot {
    uint256 blockNumber;
    uint256 timestamp;
    address user;
    uint256 healthFactor;
}
```

### 3. 错误处理

```solidity
// 使用 try-catch 处理可能的失败
try pool.getReserveData(asset) returns (DataTypes.ReserveDataLegacy memory data) {
    // 处理成功情况
} catch {
    console2.log("Failed to get reserve data for:", asset);
}
```

### 4. 性能优化

- 缓存常用的合约实例
- 避免重复的网络调用
- 使用批量操作

### 5. 安全考虑

- 不要在测试中使用真实的私钥
- 确保测试环境与生产环境隔离
- 定期更新测试数据

## 📚 参考资源

- [Foundry Book - Fork Testing](https://book.getfoundry.sh/forge/fork-testing)
- [Aave V3 Documentation](https://docs.aave.com/developers/)
- [Ethereum Mainnet Explorer](https://etherscan.io/)
- [DeFiPulse - Aave](https://defipulse.com/aave)

## 🤝 贡献

如果您发现问题或有改进建议，请：

1. 创建 Issue 描述问题
2. 提交 Pull Request 修复问题
3. 更新文档和测试用例

---

**注意：** Fork 测试会消耗 RPC 调用配额，请合理使用。建议在开发过程中使用免费的 RPC 服务，在 CI/CD 中使用付费服务以确保稳定性。