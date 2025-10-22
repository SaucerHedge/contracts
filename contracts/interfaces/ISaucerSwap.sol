// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Corrected SaucerSwap Interfaces
 * @notice Based on actual SaucerSwap V2 implementation (Uniswap V3 fork)
 * @dev References: https://github.com/saucerswaplabs/saucerswaplabs-core
 */

/**
 * @notice IERC721Receiver for NFT positions
 */
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

/**
 * @notice SaucerSwap V2 Swap Router (Based on Uniswap V3 SwapRouter)
 * @dev Contract: SwapRouter02 on Hedera
 */
interface ISaucerSwapV2Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    function exactOutputSingle(
        ExactOutputSingleParams calldata params
    ) external payable returns (uint256 amountIn);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    function exactOutput(
        ExactOutputParams calldata params
    ) external payable returns (uint256 amountIn);

    /// @notice Unwraps the contract's WHBAR balance and sends it to recipient as HBAR
    function unwrapWHBAR(
        uint256 amountMinimum,
        address recipient
    ) external payable;

    /// @notice Refunds any HBAR balance held by this contract to the `msg.sender`
    function refundETH() external payable;

    /// @notice Returns the WHBAR address
    function WHBAR() external view returns (address);
}

/**
 * @notice SaucerSwap V2 NonfungiblePositionManager (Based on Uniswap V3 NonfungiblePositionManager)
 * @dev Manages concentrated liquidity positions as NFTs
 */
interface ISaucerSwapV2NonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Creates a new position wrapped in a NFT
    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Increases the amount of liquidity in a position
    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    )
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Decreases the amount of liquidity in a position
    function decreaseLiquidity(
        DecreaseLiquidityParams calldata params
    ) external payable returns (uint256 amount0, uint256 amount1);

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    /// @notice Collects up to a maximum amount of fees owed to a specific position
    function collect(
        CollectParams calldata params
    ) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice Burns a token ID, which deletes it from the NFT contract
    function burn(uint256 tokenId) external payable;

    /// @notice Returns the position information associated with a given token ID
    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    /// @notice Refunds any HBAR balance held by this contract to the `msg.sender`
    function refundETH() external payable;

    /// @notice Unwraps the contract's WHBAR balance and sends it to recipient as HBAR
    function unwrapWHBAR(
        uint256 amountMinimum,
        address recipient
    ) external payable;

    /// @notice Enables calling multiple methods in a single call to the contract
    function multicall(
        bytes[] calldata data
    ) external payable returns (bytes[] memory results);
}

/**
 * @notice SaucerSwap V2 Pool (Based on Uniswap V3 Pool)
 */
interface ISaucerSwapV2Pool {
    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    /// @notice The currently in range liquidity available to the pool
    function liquidity() external view returns (uint128);

    /// @notice Look up information about a specific tick in the pool
    function ticks(
        int24 tick
    )
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        );

    /// @notice Returns the cumulative tick and liquidity as of each timestamp `secondsAgo` from the current block timestamp
    function observe(
        uint32[] calldata secondsAgos
    )
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        );

    /// @notice The first of the two tokens of the pool, sorted by address
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address
    function token1() external view returns (address);

    /// @notice The pool's fee in hundredths of a bip, i.e. 1e-6
    function fee() external view returns (uint24);
}

/**
 * @notice SaucerSwap V2 Factory (Based on Uniswap V3 Factory)
 */
interface ISaucerSwapV2Factory {
    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    /// @notice Creates a pool for the given two tokens and fee
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
}

/**
 * @notice SaucerSwap V2 Quoter (For getting quotes without executing)
 */
interface ISaucerSwapV2Quoter {
    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    function quoteExactInput(
        bytes memory path,
        uint256 amountIn
    ) external returns (uint256 amountOut);

    /// @notice Returns the amount in required for a given exact output swap without executing the swap
    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountIn);
}

/**
 * @notice WHBAR Interface
 */
interface IWHBAR {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

/**
 * @title Hedera-Specific Constants
 * @notice Actual contract addresses on Hedera
 */
library HederaAddresses {
    // Hedera Mainnet Addresses (as Solidity addresses)
    // Format: 0.0.X converted to address format

    // WHBAR (0.0.14802) = 0x0000000000000000000000000000000000003aD2
    address public constant WHBAR = 0x0000000000000000000000000000000000003aD2;

    // USDC (0.0.5349) = 0x00000000000000000000000000000000000014F5
    address public constant USDC = 0x00000000000000000000000000000000000014F5;

    // SAUCE (0.0.1183558) = 0x0000000000000000000000000000000000120f46
    address public constant SAUCE = 0x0000000000000000000000000000000000120f46;

    // SaucerSwap V2 Contracts - Hedera Testnet
    // SaucerSwap V2 Factory (0.0.1197038)
     address public constant SAUCERSWAP_V2_FACTORY = 0x00000000000000000000000000000000001243eE;


    // SaucerSwap V2 Router (0.0.1414040)
    address public constant SAUCERSWAP_V2_ROUTER = 0x0000000000000000000000000000000000159198;

    // SaucerSwap V2 NFT Position Manager (0.0.1308184)
    address public constant SAUCERSWAP_V2_NFT_MANAGER = 0x000000000000000000000000000000000013f418;

    // SaucerSwap V2 Quoter (0.0.1390002)
    address public constant SAUCERSWAP_V2_QUOTER = 0x0000000000000000000000000000000000153532;

    // Fee tiers (in hundredths of a bip)
    uint24 public constant FEE_LOW = 500; // 0.05%
    uint24 public constant FEE_MEDIUM = 3000; // 0.3%
    uint24 public constant FEE_HIGH = 10000; // 1%
}
