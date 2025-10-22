// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/ISaucerSwap.sol";
import "./HTSAdapter.sol";
import "./UD60x18Lib.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

/**
 * @title SaucerSwapV2Provider
 * @notice Manages concentrated liquidity positions on SaucerSwap V2
 * @dev Similar to Uniswap V3 position management
 */
contract SaucerSwapV2Provider is IERC721Receiver, HTSAdapter, UD60x18Lib {
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 60;

    // SaucerSwap V2 Position Manager - Update with actual mainnet address
    ISaucerSwapV2NonfungiblePositionManager public nonfungiblePositionManager;

    constructor(address _nftPositionManager) {
        nonfungiblePositionManager = ISaucerSwapV2NonfungiblePositionManager(
            _nftPositionManager
        );
    }

    /**
     * @notice NFT receiver callback
     */
    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* tokenId */,
        bytes calldata /* data */
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Convert price to sqrtPriceX96 format
     * @param price Price value
     * @return sqrtPriceX96 Square root price in X96 format
     */
    function priceToSqrtX96(uint256 price) public pure returns (uint160) {
        uint160 sqrtPriceX96 = uint160(
            (unwrap(ud_sqrt(ud(price))) * 2 ** 96) / 1e18
        );
        return sqrtPriceX96;
    }

    /**
     * @notice Round tick to nearest valid tick
     * @param tick Input tick
     * @return Rounded tick
     */
    function roundToNearestTick(int24 tick) public pure returns (int24) {
        int24 modTick = tick % TICK_SPACING;
        if (modTick < TICK_SPACING / 2) {
            return tick - modTick;
        } else {
            return tick + (TICK_SPACING - modTick);
        }
    }

    /**
     * @notice Mint new liquidity position
     * @param token0 First token address
     * @param token1 Second token address
     * @param amount0ToAdd Amount of token0
     * @param amount1ToAdd Amount of token1
     * @param tickLower Lower tick bound
     * @param tickUpper Upper tick bound
     * @return tokenId NFT token ID
     * @return liquidity Liquidity amount
     * @return amount0 Actual token0 amount used
     * @return amount1 Actual token1 amount used
     */
    function mintNewPosition(
        address token0,
        address token1,
        uint256 amount0ToAdd,
        uint256 amount1ToAdd,
        int24 tickLower,
        int24 tickUpper
    )
        public
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // Transfer tokens from sender
        _transferToken(token0, msg.sender, address(this), amount0ToAdd);
        _transferToken(token1, msg.sender, address(this), amount1ToAdd);

        // Approve position manager
        _approveToken(
            token0,
            address(nonfungiblePositionManager),
            amount0ToAdd
        );
        _approveToken(
            token1,
            address(nonfungiblePositionManager),
            amount1ToAdd
        );

        // Prepare mint parameters
        ISaucerSwapV2NonfungiblePositionManager.MintParams
            memory params = ISaucerSwapV2NonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: 3000, // 0.3% fee tier
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        // Mint position
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager
            .mint{value: msg.value}(params);

        // Refund unused tokens
        if (amount0 < amount0ToAdd) {
            _approveToken(token0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToAdd - amount0;
            _safeTransfer(token0, msg.sender, refund0);
        }
        if (amount1 < amount1ToAdd) {
            _approveToken(token1, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToAdd - amount1;
            _safeTransfer(token1, msg.sender, refund1);
        }

        return (tokenId, liquidity, amount0, amount1);
    }

    /**
     * @notice Collect fees from position
     * @param tokenId NFT token ID
     * @return amount0 Token0 fees collected
     * @return amount1 Token1 fees collected
     */
    function collectAllFees(
        uint256 tokenId
    ) public returns (uint256 amount0, uint256 amount1) {
        ISaucerSwapV2NonfungiblePositionManager.CollectParams
            memory params = ISaucerSwapV2NonfungiblePositionManager
                .CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
        return (amount0, amount1);
    }

    /**
     * @notice Increase liquidity in existing position
     * @param tokenId NFT token ID
     * @param amount0ToAdd Amount of token0 to add
     * @param amount1ToAdd Amount of token1 to add
     * @return liquidity New liquidity amount
     * @return amount0 Actual token0 amount used
     * @return amount1 Actual token1 amount used
     */
    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amount0ToAdd,
        uint256 amount1ToAdd
    )
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        // Get position info
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);

        // Transfer tokens
        _transferToken(token0, msg.sender, address(this), amount0ToAdd);
        _transferToken(token1, msg.sender, address(this), amount1ToAdd);

        // Approve tokens
        _approveToken(
            token0,
            address(nonfungiblePositionManager),
            amount0ToAdd
        );
        _approveToken(
            token1,
            address(nonfungiblePositionManager),
            amount1ToAdd
        );

        // Prepare increase parameters
        ISaucerSwapV2NonfungiblePositionManager.IncreaseLiquidityParams
            memory params = ISaucerSwapV2NonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amount0ToAdd,
                    amount1Desired: amount1ToAdd,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        // Increase liquidity
        (liquidity, amount0, amount1) = nonfungiblePositionManager
            .increaseLiquidity{value: msg.value}(params);

        return (liquidity, amount0, amount1);
    }

    /**
     * @notice Decrease liquidity from position
     * @param tokenId NFT token ID
     * @param liquidity Liquidity amount to remove
     * @return amount0 Token0 amount withdrawn
     * @return amount1 Token1 amount withdrawn
     */
    function decreaseLiquidityCurrentRange(
        uint256 tokenId,
        uint128 liquidity
    ) public returns (uint256 amount0, uint256 amount1) {
        ISaucerSwapV2NonfungiblePositionManager.DecreaseLiquidityParams
            memory params = ISaucerSwapV2NonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
            params
        );
        return (amount0, amount1);
    }

    /**
     * @notice Burn NFT position (must have no liquidity)
     * @param tokenId NFT token ID
     */
    function burnPosition(uint256 tokenId) external {
        nonfungiblePositionManager.burn(tokenId);
    }
}
