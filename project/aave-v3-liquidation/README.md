# Aave V3 Flash Loan Liquidation

一个使用闪电贷进行 Aave V3 清算的智能合约项目。

## 📋 项目概述

本项目实现了一个自动化的 Aave V3 清算机器人，通过闪电贷获取资金来清算不良债务，并通过 DEX 交换获得利润。

### 主要功能

- 🔄 **闪电贷清算**: 使用 Aave V3 闪电贷进行无本金清算
- 💱 **自动交换**: 通过 Uniswap V4 自动交换抵押品为债务资产
- 💰 **利润分配**: 自动分配利润给 Builder 和合约拥有者
- 🛡️ **安全机制**: 包含暂停、重入保护等安全功能
- 🎯 **精确清算**: 支持部分清算和最大债务清算

### 核心合约

- `AaveV3FlashLoanSimple.sol` - 主要的清算合约

## 🛠️ 技术栈

**Foundry** - 以太坊开发工具链

Foundry 包含:

-   **Forge**: 以太坊测试框架
-   **Cast**: 与 EVM 智能合约交互的工具
-   **Anvil**: 本地以太坊节点
-   **Chisel**: Solidity REPL

## 📚 文档

- [Foundry 官方文档](https://book.getfoundry.sh/)
- [Fork 测试指南](./FORK_TESTING.md) - 详细的 mainnet fork 测试说明

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
