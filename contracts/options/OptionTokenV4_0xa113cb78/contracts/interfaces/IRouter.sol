// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IRouter { 
    function factory() external view returns (address);
    function pairFor(address tokenA, address tokenB, bool stable) external view returns (address pair);
    function addLiquidity(address tokenA,address tokenB,bool stable,uint amountADesired,uint amountBDesired,uint amountAMin,uint amountBMin,address to,uint deadline) external returns (uint amountA, uint amountB, uint liquidity);
    function getReserves(address tokenA, address tokenB, bool stable) external view returns (uint reserveA, uint reserveB);
}
