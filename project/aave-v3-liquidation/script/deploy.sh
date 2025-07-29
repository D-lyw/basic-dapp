#!/bin/bash

# 加载环境变量
source .env

# 部署到 Sepolia 测试网
# forge script script/Deploy.s.sol:DeployScript \
#     --rpc-url $SEPOLIA_RPC_URL \
#     --broadcast \
#     -vvvv

# # 部署到主网
# forge script script/Deploy.s.sol:DeployScript \
#     --rpc-url $MAINNET_RPC_URL \
#     --broadcast \
#     -vvvv 

部署到 Base 主网
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $BASE_MAINNET_RPC_URL \
    --broadcast \
    -vvvv 