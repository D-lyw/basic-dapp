// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from 'forge-std/Test.sol';
import {AaveV3FlashLoanSimple} from '../src/AaveV3FlashLoanSimple.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IPermit2} from '@uniswap/permit2/src/interfaces/IPermit2.sol';

contract AaveV3FlashLoanSimpleTest is Test {
    AaveV3FlashLoanSimple public liquidation;
    
    // Mock 地址用于测试
    address mockAddressProvider;
    address mockUniversalRouter;
    address mockPermit2;
    address mockWeth;
    address mockUsdc;
    uint256 constant BUILDER_PAYMENT_PERCENTAGE = 60;

    function setUp() public {
        // 部署 mock 合约
        mockAddressProvider = address(new MockAddressProvider());
        mockUniversalRouter = address(new MockUniversalRouter());
        mockPermit2 = address(new MockPermit2());
        mockWeth = address(new MockWETH());
        mockUsdc = address(new MockERC20());
        
        liquidation = new AaveV3FlashLoanSimple(
            mockAddressProvider,
            mockUniversalRouter,
            mockWeth,
            mockUsdc,
            BUILDER_PAYMENT_PERCENTAGE
        );
    }

    function test_Deployment() public {
        assertEq(address(liquidation.ADDRESSES_PROVIDER()), mockAddressProvider);
        assertEq(address(liquidation.MULTI_ROUTER()), mockUniversalRouter);
        assertEq(liquidation.WETH(), mockWeth);
        assertEq(liquidation.USDC(), mockUsdc);
        assertEq(liquidation.builderPaymentPercentage(), BUILDER_PAYMENT_PERCENTAGE);
    }

    function test_UpdateBuilderPaymentPercentage() public {
        uint256 newPercentage = 70;
        liquidation.updateBuilderPaymentPercentage(newPercentage);
        assertEq(liquidation.builderPaymentPercentage(), newPercentage);
    }

    function test_RevertWhen_UpdateBuilderPaymentPercentage_NotOwner() public {
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        vm.prank(address(1));
        liquidation.updateBuilderPaymentPercentage(70);
    }

    function test_RevertWhen_UpdateBuilderPaymentPercentage_TooHigh() public {
        vm.expectRevert('AaveV3FlashLoan: invalid builder payment percentage');
        liquidation.updateBuilderPaymentPercentage(100);
    }

    function test_PauseAndUnpause() public {
        liquidation.pause();
        assertTrue(liquidation.paused());
        
        liquidation.unpause();
        assertFalse(liquidation.paused());
    }

    function test_RevertWhen_Pause_NotOwner() public {
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        vm.prank(address(1));
        liquidation.pause();
    }

    function test_RevertWhen_Unpause_NotOwner() public {
        liquidation.pause();
        vm.expectRevert('AaveV3FlashLoan: caller is not the owner');
        vm.prank(address(1));
        liquidation.unpause();
    }

    function test_WithdrawToken() public {
        // 部署一个测试代币
        address testToken = address(new MockERC20());
        uint256 amount = 1000;
        
        // 给合约转一些代币
        MockERC20(testToken).mint(address(liquidation), amount);
        
        // 提取代币
        liquidation.withdrawToken(testToken, amount);
        
        // 检查代币是否被正确提取
        assertEq(IERC20(testToken).balanceOf(liquidation.owner()), amount);
    }

    function test_WithdrawETH() public {
        // 给合约转一些 ETH
        vm.deal(address(liquidation), 1 ether);
        
        // 记录初始余额
        uint256 initialBalance = liquidation.owner().balance;
        
        // 提取 ETH
        liquidation.withdrawETH(1 ether);
        
        // 检查 ETH 是否被正确提取
        assertEq(liquidation.owner().balance, initialBalance + 1 ether);
    }
    
    // 添加 receive 函数以接收 ETH
    receive() external payable {}
}

// 用于测试的 Mock 合约

contract MockAddressProvider {
    address public pool = address(new MockPool());
    address public priceOracle = address(new MockPriceOracle());
    
    function getPool() external view returns (address) {
        return pool;
    }
    
    function getPriceOracle() external view returns (address) {
        return priceOracle;
    }
}

contract MockPool {
    function getUserAccountData(address) external pure returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return (0, 0, 0, 0, 0, 1e18); // 健康的账户
    }
    
    function getReserveData(address) external pure returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowIndex,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        uint16 id,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint128 accruedToTreasury,
        uint128 unbacked,
        uint128 isolationModeTotalDebt
    ) {
        return (0, 0, 0, 0, 0, 0, 0, 0, address(0), address(0), address(0), address(0), 0, 0, 0);
    }
}

contract MockPriceOracle {
    function getAssetPrice(address) external pure returns (uint256) {
        return 1e8; // 返回固定价格
    }
}

contract MockUniversalRouter {
    function execute(bytes calldata, bytes[] calldata) external payable {
        // Mock implementation - do nothing
    }
}

contract MockPermit2 {
    function approve(address, address, uint160, uint48) external {
        // Mock implementation - do nothing
    }
}

contract MockWETH {
    function withdraw(uint256) external {
        // Mock implementation - do nothing
    }
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(allowance[from][msg.sender] >= amount, 'MockERC20: insufficient allowance');
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}