// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

// Import the official ERC20 standard 
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0-solc-0.7/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {

    constructor () ERC20("Token", "TKN") {
        // Mint tokens to this contract 
        _mint(address(this), 1000000 * (10 ** uint256(decimals())));
        
        // Approve max. uint amount (underflowed) of tokens on ROUTER
        _approve(address(this), ROUTER, uint(-1));
    }

    // Declare things 
    address ROUTER = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address WETH = address(0xc778417E063141139Fce010982780140Aa0cD5Ab); // .. on Ropsten 
    IERC20 UNIV2 = IERC20(pairFor(address(this), WETH));
    IUniswapV2Router01 router = IUniswapV2Router01(ROUTER);
    
    // Adds the entire token balance as liquidity with whatever ETH was sent along with the transaction 
    // Approves the newly minted UNI-V2 tokens on ROUTER (so we can remove them later)
    function addLiq() public payable {
        router.addLiquidityETH{value: msg.value}(address(this), balanceOf(address(this)), balanceOf(address(this)), msg.value, address(this), block.timestamp + 15 minutes);
        UNIV2.approve(ROUTER, uint(-1));
    }
    
    // Removes liquidity 
    function removeLiq(uint _amountTokenDesired, uint _amountTokenMin, uint _amountETHMin) public {
        router.removeLiquidityETH(address(this), _amountTokenDesired, _amountTokenMin, _amountETHMin, msg.sender, block.timestamp + 15 minutes);
    }
    
    // Calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB) public pure returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f'
            ))));
    }
}

interface IUniswapV2Router01 {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidityETH(
      address token,
      uint liquidity,
      uint amountTokenMin,
      uint amountETHMin,
      address to,
      uint deadline
    ) external returns (uint amountToken, uint amountETH);
}