# Flashloan

闪电贷是去中心化金融（DeFi）中的一项创新功能，允许用户无需抵押即可借入大量资金，但需在同一笔交易内完成借款、使用和还款。若还款失败，整个交易将被回滚，确保资金安全。闪电贷的核心逻辑基于以太坊交易的原子性（要么全部成功，要么全部失败）。

闪电贷的核心特点

+ 无需抵押：用户无需提供任何抵押品即可借款。
+ 单交易完成：借款、使用、还款必须在同一笔交易中完成。
+ 高灵活性：资金可用于套利、清算、抵押置换等场景。
+ 低风险：若未按时还款，交易自动回滚，协议无损失。

主流 Uniswap、AAVE 等 Defi 产品，均提供 flashloan 相关接口

+ https://docs.uniswap.org/contracts/v3/guides/flash-integrations/inheritance-constructors
+ https://aave.com/docs/developers/flash-loans
<!-- TODO: -->