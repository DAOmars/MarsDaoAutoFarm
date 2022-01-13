// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./lib/Ownable.sol";
import "./lib/IPancakeRouter.sol";
import "./lib/IPancakeswapFarm.sol";
import "./lib/IPancakePair.sol";
import "./lib/IPancakeFactory.sol";
import "./lib/ERC20.sol";
import "./lib/IERC20.sol";
import "./lib/SafeERC20.sol";
import "./lib/Address.sol";
import "./lib/Context.sol";
import "./lib/Pausable.sol";
import "./lib/ReentrancyGuard.sol";
import "./lib/SafeMath.sol";
import "./lib/EnumerableSet.sol";
import "./lib/IMarsAutoFarm.sol";
import "./lib/IERC20Metadata.sol";
import "./lib/IStrategy.sol";
//import "./lib/console.sol";
pragma experimental ABIEncoderV2;


contract StratX is Ownable, ReentrancyGuard, Pausable {
    // Maximises yields in pancakeswap

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public isCAKEStaking; // only for staking CAKE using pancakeswap's native CAKE staking contract.

    
    uint256 public pid; // pid of pool in farmContractAddress
    uint256 public marsPid;//// id of pool in marsAutoFarmAddress
    address public wantAddress;
    address public token0Address;
    address public token1Address;
    address public constant earnedAddress=0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;//CAKE
    address public constant farmContractAddress=0x73feaa1eE314F8c655E354234017bE2193C9E24E; // address of farm, eg, PCS, Thugs etc.
    address public constant uniRouterAddress=0x10ED43C718714eb63d5aA57B78B54704E256024E; // uniswap, pancakeswap etc
    IPancakeFactory public constant uniFactory=IPancakeFactory(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73);
    address public constant wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant busdAddress=0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address public marsAutoFarmAddress;
    address immutable public marsTokenAddress;
    address public adminAddress;
 
    uint256 public wantLockedTotal = 0;
    uint256 public sharesTotal = 0;

    address immutable public dev25;
    address immutable public dev75;

    
    uint256 public constant MaxBP = 10000; // 100%

    uint256 public buyBackRate = 10000;
    uint256 public constant buyBackRateUL = 7000;//70%
    uint256 public constant buyBackRateLL = 3000;//30%
    uint256 public swapSlippageBP=900;

    uint256 public burnRate = 10000;
    uint256 public constant burnRateUL = 4500;//45%
    uint256 public constant burnRateLL = 1000;//10%
    address public constant burnAddress =
        0x000000000000000000000000000000000000dEaD;

    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;
    address[][] public router0;
    address[][] public router1;
    address[][] public router2;

    modifier onlyAdminAddress() {
        require(msg.sender == adminAddress, "Not authorised");
        _;
    }

    constructor(
        address _adminAddress,
        address _marsAutoFarmAddress,
        address _marsTokenAddress,
        address _dev25,
        address _dev75
    ) public {
        adminAddress = _adminAddress;
        marsAutoFarmAddress = _marsAutoFarmAddress;
        marsTokenAddress = _marsTokenAddress;
        dev25=_dev25;
        dev75=_dev75;
        transferOwnership(marsAutoFarmAddress);
    }

    
    function activateStrategy(uint256 poolId,//marsAutoFarm
                            address _wantAddress,
                            uint256 _farmPid) external onlyOwner returns (bool){

        require(wantAddress==address(0),"already activated");
        require(marsTokenAddress!=_wantAddress,
        "marsTokenAddress address cannot be equal to _wantAddress");

        marsPid=poolId;
        wantAddress=_wantAddress;
        if(_farmPid==0){
            isCAKEStaking = true;
        }

        pid = _farmPid;
        router2.push([earnedAddress, busdAddress, marsTokenAddress]);
        router2.push([earnedAddress, wbnbAddress, busdAddress, marsTokenAddress]);
            
        if (!isCAKEStaking) {
            token0Address = IPancakePair(_wantAddress).token0();
            token1Address = IPancakePair(_wantAddress).token1();
            require(uniFactory.getPair(token0Address,token1Address)!= address(0), 
            "LP token V1 is not supported");
            token0ToEarnedPath = [token0Address, wbnbAddress, earnedAddress];
            token1ToEarnedPath = [token1Address, wbnbAddress, earnedAddress];

            if (token0Address == wbnbAddress) {
                router0.push([earnedAddress, token0Address]);
                token0ToEarnedPath = [token0Address, earnedAddress];
            }else{
                if(uniFactory.getPair(earnedAddress,token0Address)!=address(0)){
                    router0.push([earnedAddress, token0Address]);
                    router1.push([earnedAddress, token0Address, token1Address]);
                }
                router0.push([earnedAddress,wbnbAddress,token0Address]);
            }

            if (token1Address == wbnbAddress) {
                router1.push([earnedAddress, token1Address]);
                token1ToEarnedPath = [token1Address, earnedAddress];
            }else{
                if(uniFactory.getPair(earnedAddress,token1Address)!=address(0)){
                    router1.push([earnedAddress, token1Address]);
                    router0.push([earnedAddress, token1Address, token0Address]);
                }
                router1.push([earnedAddress,wbnbAddress,token1Address]);
            }
        }

        return true;
    }

    function _getBestPath(uint256 amountIn,address[][] memory router) 
    internal view returns(address[] memory,uint256){
        uint256 amountOut=0;
        uint256 bestI=0;
        for(uint256 i=0;i<router.length;i++){
            uint256[] memory amounts = IPancakeRouter02(uniRouterAddress).getAmountsOut(amountIn, router[i]);
            if(amounts[amounts.length.sub(1)]>amountOut){
                amountOut=amounts[amounts.length.sub(1)];
                bestI=i;
            }
        }
        
        return (router[bestI],amountOut);
    }

    function getEarnedToBusdPath(uint256 amountIn) 
    public view returns(address[] memory,uint256){
        return _getBestPath(amountIn,router2);
    }

    function getPathForToken0(uint256 amountIn) 
    public view returns(address[] memory,uint256){
        return _getBestPath(amountIn,router0);
    }

    function getPathForToken1(uint256 amountIn) 
    public view returns(address[] memory,uint256){
        return _getBestPath(amountIn,router1);
    }

    // Receives new deposits from user
    function deposit(address _userAddress, uint256 _wantAmt)
        public
        onlyOwner
        whenNotPaused
        returns (uint256)
    {
        IERC20(wantAddress).safeTransferFrom(
            _userAddress,
            address(this),
            _wantAmt
        );

        uint256 sharesAdded = _wantAmt;
        if (wantLockedTotal > 0 && sharesTotal>0) {
            sharesAdded = _wantAmt
                .mul(sharesTotal)
                .div(wantLockedTotal);
        }
        sharesTotal = sharesTotal.add(sharesAdded);

        _farm();
        _helpToEarn();

        return sharesAdded;
    }

    function farm() public nonReentrant {
        _farm();
    }

    function _farm() internal {
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if(wantAmt>0){
            wantLockedTotal = wantLockedTotal.add(wantAmt);
            IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

            if (isCAKEStaking) {
                IPancakeswapFarm(farmContractAddress).enterStaking(wantAmt); // Just for CAKE staking, we dont use deposit()
            } else {
                IPancakeswapFarm(farmContractAddress).deposit(pid, wantAmt);
            }
        }
    }

    function withdraw(address _userAddress, uint256 _wantAmt, bool isEmergency)
        public
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        require(_wantAmt > 0, "_wantAmt <= 0");


        if (isCAKEStaking) {
            IPancakeswapFarm(farmContractAddress).leaveStaking(_wantAmt); // Just for CAKE staking, we dont use withdraw()
        } else {
            IPancakeswapFarm(farmContractAddress).withdraw(pid, _wantAmt);
        }


        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal.sub(sharesRemoved);
        wantLockedTotal = wantLockedTotal.sub(_wantAmt);

        IERC20(wantAddress).safeTransfer(_userAddress, _wantAmt);
        if(!isEmergency){ _helpToEarn();}
        return sharesRemoved;
    }

    function lastEarnBlock() public view returns(uint256){
        return IMarsAutoFarm(marsAutoFarmAddress).poolLastEarnBlock(marsPid);
    }

    function earn() public {
        if(!paused()){
            _earn(false);
        }else{
            //lastEarnBlock = block.number;
            IMarsAutoFarm(marsAutoFarmAddress).updateLastEarnBlock(marsPid);
        }
    }

    function _helpToEarn() internal{
        (address stratThatNeedsEarnings,uint256 lastBlock)=IMarsAutoFarm(marsAutoFarmAddress).getStratThatNeedsEarnings();
        if(lastBlock < block.number){
            if(stratThatNeedsEarnings==address(this)){
                _earn(true);
            }else{
                IStrategy(stratThatNeedsEarnings).earn();
            }
        }
    }

    function _earn(bool isUser) internal {
        if(!isUser){
            // Harvest farm tokens
            if (isCAKEStaking) {
                IPancakeswapFarm(farmContractAddress).leaveStaking(0); // Just for CAKE staking, we dont use withdraw()
            } else {
                IPancakeswapFarm(farmContractAddress).withdraw(pid, 0);
            }
        }

        // Converts farm tokens into want tokens
        
        if (isCAKEStaking) {
            IMarsAutoFarm(marsAutoFarmAddress).updateLastEarnBlock(marsPid);
            _farm();
            return;
        }

        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        earnedAmt = distributeFees(earnedAmt);
        earnedAmt = buyBack(earnedAmt);

        if(earnedAmt<2){
            IMarsAutoFarm(marsAutoFarmAddress).updateLastEarnBlock(marsPid);
            return;
        }

        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            earnedAmt
        );
        uint256 halfAmount=earnedAmt.div(2);
        address[] memory path;
        uint256 amountOut;
        if (earnedAddress != token0Address) {
            // Swap half earned to token0
            (path,amountOut)=getPathForToken0(halfAmount);
            _swap(halfAmount,amountOut,path);
        }

        if (earnedAddress != token1Address) {
            // Swap half earned to token1
            (path,amountOut)=getPathForToken1(halfAmount);
            _swap(halfAmount,amountOut,path);
        }

        // Get want tokens, ie. add liquidity
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token0Amt > 0 && token1Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );
            IPancakeRouter02(uniRouterAddress).addLiquidity(
                token0Address,
                token1Address,
                token0Amt,
                token1Amt,
                0,
                0,
                address(this),
                block.timestamp.add(600)
            );
        }

        IMarsAutoFarm(marsAutoFarmAddress).updateLastEarnBlock(marsPid);

        _farm();
    }

    function buyBack(uint256 _earnedAmt) internal returns (uint256) {

        uint256 buyBackAmt = _earnedAmt.mul(buyBackRate).div(MaxBP);

        if (buyBackAmt == 0) {
            return _earnedAmt;
        }

        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            buyBackAmt
        );

        (address[] memory path,uint256 amountOut)=getEarnedToBusdPath(buyBackAmt);

        _swap(buyBackAmt,amountOut,path);
        
        return _earnedAmt.sub(buyBackAmt);
    }

    function distributeReward() external {
        uint256 rewardAmount=IERC20(marsTokenAddress).balanceOf(address(this));
        //min amount 1e7
        if(rewardAmount>1e7 && sharesTotal>0){
            uint256 burnAmount=rewardAmount.mul(burnRate).div(MaxBP);
            IERC20(marsTokenAddress).safeTransfer(burnAddress, burnAmount);
            rewardAmount=rewardAmount.sub(burnAmount);
            IERC20(marsTokenAddress).safeIncreaseAllowance(marsAutoFarmAddress, rewardAmount);
            require(IMarsAutoFarm(marsAutoFarmAddress).chargePool(marsPid,rewardAmount,sharesTotal),
            "pool charging fail");
        }
    }

    function distributeFees(uint256 _earnedAmt) internal returns (uint256) {
        if (_earnedAmt > 0) {
            uint256 fee75 =_earnedAmt.mul(300).div(MaxBP);//3%
            uint256 fee25 = _earnedAmt.mul(100).div(MaxBP);//1%
            IERC20(earnedAddress).safeTransfer(dev75, fee75);
            IERC20(earnedAddress).safeTransfer(dev25, fee25);
            _earnedAmt = _earnedAmt.sub(fee75.add(fee25));
        }

        return _earnedAmt;
    }

    function convertDustToEarned() public whenNotPaused {
        require(!isCAKEStaking, "isCAKEStaking");

        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && token0Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );

            // Swap all dust tokens to earned tokens
            _swap(token0Amt,0,token0ToEarnedPath);
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && token1Amt > 0) {
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );
            // Swap all dust tokens to earned tokens
            _swap(token1Amt,0,token1ToEarnedPath);
        }
    }

    function pause() public onlyAdminAddress {
        _pause();
    }

    function unpause() external onlyAdminAddress{
        _unpause();
    }

    function setRouter0(address[][] memory _router0) public onlyAdminAddress {
        for(uint256 i=0;i<_router0.length;i++){
            require(_router0[i][0]==earnedAddress);
            require(_router0[i][_router0[i].length.sub(1)]==token0Address);
        }
        delete router0;
        router0=_router0;
    }

    function setRouter1(address[][] memory _router1) public onlyAdminAddress {
        for(uint256 i=0;i<_router1.length;i++){
            require(_router1[i][0]==earnedAddress);
            require(_router1[i][_router1[i].length.sub(1)]==token1Address);
        }
        delete router1;
        router1=_router1;
    }

    function setRouter2(address[][] memory _router2) public onlyAdminAddress {
        for(uint256 i=0;i<_router2.length;i++){
            require(_router2[i][0]==earnedAddress);
            require(_router2[i][_router2[i].length.sub(1)]==marsTokenAddress);
        }
        delete router2;
        router2=_router2;
    }

    function setBurnRate(uint256 _burnRate) public onlyAdminAddress{
        require(burnRate <= burnRateUL, "too high");
        require(burnRate >= burnRateLL, "too low");
        burnRate = _burnRate;
    }

    function setbuyBackRate(uint256 _buyBackRate) public onlyAdminAddress{
        require(buyBackRate <= buyBackRateUL, "too high");
        require(buyBackRate >= buyBackRateLL, "too low");
        buyBackRate = _buyBackRate;
    }

    function setGov(address _adminAddress) public onlyAdminAddress{
        require(_adminAddress!=address(0),"zero address!");
        //first call
        if(buyBackRate == 10000){
            buyBackRate=4845;//48,45%
            burnRate = 2000;//20%
        }
        adminAddress = _adminAddress;
    }

    function setSwapSlippageBP(uint256 _swapSlippageBP) external onlyAdminAddress{
        require(_swapSlippageBP<1000,"should be between 0-1000");
        swapSlippageBP=_swapSlippageBP;
    }

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public onlyAdminAddress{
        require(_token != earnedAddress, "!safe");
        require(_token != wantAddress, "!safe");
        require(_token != marsTokenAddress, "!safe");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _swap(
        uint256 _amountIn,
        uint256 _amountOut,
        address[] memory _path
    ) internal {

        if(_amountIn>0){

            uint256 amountOut = _amountOut.mul(swapSlippageBP).div(1000);

            IPancakeRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn,
                amountOut,
                _path,
                address(this),
                block.timestamp.add(600)
            );
            
        }
    }
}