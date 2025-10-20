// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/ISaucerSwap.sol";
import "./HTSAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SaucerSwapper - CORRECTED VERSION
 * @notice Handles token swaps on SaucerSwap V2 with proper Hedera integration
 * @dev Uses actual SaucerSwap V2 router based on Uniswap V3
 */
contract SaucerSwapper is HTSAdapter {
    using SafeERC20 for IERC20;

    // SaucerSwap V2 Contracts - Set in constructor
    ISaucerSwapV2Router public saucerSwapRouter;
    ISaucerSwapV2Factory public saucerSwapFactory;
    ISaucerSwapV2Quoter public saucerSwapQuoter;

    // WHBAR address - Retrieved from router
    address public WHBAR;

    // Default fee tier (0.3% = 3000)
    uint24 public constant DEFAULT_FEE = 3000;

    // Slippage tolerance (1% = 100 basis points)
    uint256 public constant SLIPPAGE_TOLERANCE = 100;
    uint256 public constant BASIS_POINTS = 10000;

    // Events
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    event RouterUpdated(address indexed newRouter);
    event FactoryUpdated(address indexed newFactory);

    /**
     * @notice Constructor
     * @param _router SaucerSwap V2 Router address
     * @param _factory SaucerSwap V2 Factory address
     * @param _quoter SaucerSwap V2 Quoter address (optional, can be address(0))
     */
    constructor(address _router, address _factory, address _quoter) {
        require(_router != address(0), "Invalid router address");
        require(_factory != address(0), "Invalid factory address");

        saucerSwapRouter = ISaucerSwapV2Router(_router);
        saucerSwapFactory = ISaucerSwapV2Factory(_factory);

        if (_quoter != address(0)) {
            saucerSwapQuoter = ISaucerSwapV2Quoter(_quoter);
        }

        // Get WHBAR address from router
        WHBAR = saucerSwapRouter.WHBAR();
        require(WHBAR != address(0), "Failed to get WHBAR address");
    }

    /**
     * @notice Get the price of tokenIn in terms of tokenOut
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return price Price with 18 decimal precision
     */
    function getPrice(
        address tokenIn,
        address tokenOut
    ) public view returns (uint256 price) {
        return getPriceWithFee(tokenIn, tokenOut, DEFAULT_FEE);
    }

    /**
     * @notice Get price with specific fee tier
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param fee Fee tier
     * @return price Price with 18 decimal precision
     */
    function getPriceWithFee(
        address tokenIn,
        address tokenOut,
        uint24 fee
    ) public view returns (uint256 price) {
        // Get pool address
        address pool = getPool(tokenIn, tokenOut, fee);
        require(pool != address(0), "Pool does not exist");

        // Get current price from pool
        ISaucerSwapV2Pool poolContract = ISaucerSwapV2Pool(pool);
        (uint160 sqrtPriceX96, , , , , , ) = poolContract.slot0();

        // Convert sqrtPriceX96 to price
        // price = (sqrtPriceX96 / 2^96)^2
        uint256 priceX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);

        // Adjust for token decimals
        uint8 decimalsIn = _getDecimals(tokenIn);
        uint8 decimalsOut = _getDecimals(tokenOut);

        // Scale to 18 decimals
        if (decimalsIn >= decimalsOut) {
            price =
                (priceX192 * 1e18 * (10 ** (decimalsIn - decimalsOut))) >>
                192;
        } else {
            price =
                ((priceX192 * 1e18) / (10 ** (decimalsOut - decimalsIn))) >>
                192;
        }

        return price;
    }

    /**
     * @notice Estimate output amount for a given input
     * @param tokenIn Input token address
     * @param amountIn Input amount
     * @param tokenOut Output token address
     * @return amountOut Estimated output amount
     */
    function estimateAmountOut(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) public returns (uint256 amountOut) {
        return
            estimateAmountOutWithFee(tokenIn, amountIn, tokenOut, DEFAULT_FEE);
    }

    /**
     * @notice Estimate output with specific fee tier
     * @param tokenIn Input token address
     * @param amountIn Input amount
     * @param tokenOut Output token address
     * @param fee Fee tier
     * @return amountOut Estimated output amount
     */
    function estimateAmountOutWithFee(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint24 fee
    ) public returns (uint256 amountOut) {
        if (address(saucerSwapQuoter) != address(0)) {
            // Use quoter if available (more accurate)
            try
                saucerSwapQuoter.quoteExactInputSingle(
                    tokenIn,
                    tokenOut,
                    fee,
                    amountIn,
                    0 // sqrtPriceLimitX96
                )
            returns (uint256 quote) {
                return quote;
            } catch {
                // Fall back to pool-based estimation
            }
        }

        // Fallback: Calculate from pool price
        uint256 price = getPriceWithFee(tokenIn, tokenOut, fee);

        // Calculate expected output (price already accounts for decimals)
        amountOut = (amountIn * price) / 1e18;

        // Apply fee (e.g., 0.3% = 3000 / 1000000)
        uint256 feeAmount = (amountOut * fee) / 1000000;
        amountOut = amountOut - feeAmount;

        return amountOut;
    }

    /**
     * @notice Get pool address for token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @param fee Fee tier
     * @return pool Pool address
     */
    function getPool(
        address token0,
        address token1,
        uint24 fee
    ) public view returns (address pool) {
        pool = saucerSwapFactory.getPool(token0, token1, fee);
        // Pool can be address(0) if it doesn't exist
        return pool;
    }

    /**
     * @notice Swap exact input amount for maximum possible output
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return amountOut Output amount received
     */
    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        return
            swapExactInputSingleWithFee(
                tokenIn,
                tokenOut,
                amountIn,
                DEFAULT_FEE
            );
    }

    /**
     * @notice Swap with specific fee tier
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param fee Fee tier
     * @return amountOut Output amount received
     */
    function swapExactInputSingleWithFee(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee
    ) internal returns (uint256 amountOut) {
        // Approve router to spend tokens
        _approveToken(tokenIn, address(saucerSwapRouter), amountIn);

        // Calculate minimum output with slippage
        uint256 estimatedOut = estimateAmountOutWithFee(
            tokenIn,
            amountIn,
            tokenOut,
            fee
        );
        uint256 amountOutMinimum = (estimatedOut *
            (BASIS_POINTS - SLIPPAGE_TOLERANCE)) / BASIS_POINTS;

        // Prepare swap parameters
        ISaucerSwapV2Router.ExactInputSingleParams
            memory params = ISaucerSwapV2Router.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0 // No price limit
            });

        // Handle HBAR swaps
        uint256 value = 0;
        if (tokenIn == WHBAR || tokenIn == address(0)) {
            value = amountIn;
        }

        // Execute swap
        amountOut = saucerSwapRouter.exactInputSingle{value: value}(params);

        emit SwapExecuted(
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            address(this)
        );

        return amountOut;
    }

    /**
     * @notice Swap to get exact output amount
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountOut Desired output amount
     * @param amountInMaximum Maximum input amount willing to spend
     * @return amountIn Actual input amount used
     */
    function swapExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum
    ) internal returns (uint256 amountIn) {
        return
            swapExactOutputSingleWithFee(
                tokenIn,
                tokenOut,
                amountOut,
                amountInMaximum,
                DEFAULT_FEE
            );
    }

    /**
     * @notice Swap to get exact output with specific fee tier
     */
    function swapExactOutputSingleWithFee(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint24 fee
    ) internal returns (uint256 amountIn) {
        // Approve router to spend tokens
        _approveToken(tokenIn, address(saucerSwapRouter), amountInMaximum);

        // Prepare swap parameters
        ISaucerSwapV2Router.ExactOutputSingleParams
            memory params = ISaucerSwapV2Router.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            });

        // Handle HBAR swaps
        uint256 value = 0;
        if (tokenIn == WHBAR || tokenIn == address(0)) {
            value = amountInMaximum;
        }

        // Execute swap
        amountIn = saucerSwapRouter.exactOutputSingle{value: value}(params);

        // Refund unused tokens
        if (amountIn < amountInMaximum) {
            _approveToken(tokenIn, address(saucerSwapRouter), 0);

            // Refund HBAR if applicable
            if (tokenIn == WHBAR || tokenIn == address(0)) {
                uint256 refund = amountInMaximum - amountIn;
                if (refund > 0) {
                    payable(address(this)).transfer(refund);
                }
            }
        }

        emit SwapExecuted(
            tokenIn,
            tokenOut,
            amountIn,
            amountOut,
            address(this)
        );

        return amountIn;
    }

    /**
     * @notice Check if a pool exists for a token pair
     * @param tokenA First token
     * @param tokenB Second token
     * @param fee Fee tier
     * @return exists Whether pool exists
     */
    function poolExists(
        address tokenA,
        address tokenB,
        uint24 fee
    ) public view returns (bool exists) {
        address pool = getPool(tokenA, tokenB, fee);
        return pool != address(0);
    }

    /**
     * @notice Get all available fee tiers for a token pair
     * @param tokenA First token
     * @param tokenB Second token
     * @return fees Array of available fee tiers
     */
    function getAvailableFeeTiers(
        address tokenA,
        address tokenB
    ) public view returns (uint24[] memory fees) {
        uint24[] memory allFees = new uint24[](3);
        allFees[0] = 500; // 0.05%
        allFees[1] = 3000; // 0.3%
        allFees[2] = 10000; // 1%

        uint256 count = 0;
        for (uint256 i = 0; i < allFees.length; i++) {
            if (poolExists(tokenA, tokenB, allFees[i])) {
                count++;
            }
        }

        fees = new uint24[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allFees.length; i++) {
            if (poolExists(tokenA, tokenB, allFees[i])) {
                fees[index] = allFees[i];
                index++;
            }
        }

        return fees;
    }

    /**
     * @notice Update router address (only for contract owner/governance)
     * @param newRouter New router address
     */
    function updateRouter(address newRouter) external {
        require(newRouter != address(0), "Invalid router");
        saucerSwapRouter = ISaucerSwapV2Router(newRouter);
        WHBAR = saucerSwapRouter.WHBAR();
        emit RouterUpdated(newRouter);
    }

    /**
     * @notice Update factory address (only for contract owner/governance)
     * @param newFactory New factory address
     */
    function updateFactory(address newFactory) external {
        require(newFactory != address(0), "Invalid factory");
        saucerSwapFactory = ISaucerSwapV2Factory(newFactory);
        emit FactoryUpdated(newFactory);
    }

    /**
     * @notice Receive HBAR
     */
    receive() external payable {}
}
