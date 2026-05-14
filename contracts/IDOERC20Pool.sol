// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./TokenLockerFactory.sol";
contract IDOERC20Pool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    struct FinInfo {
        uint256 tokenPrice; // one token in erc20pay WEI
        uint256 softCap;
        uint256 hardCap;
        uint256 minPayment;
        uint256 maxPayment;
        uint256 listingPrice; // one token in WEI
        uint256 lpInterestRate;
    }

    struct Timestamps {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 unlockTimestamp;
    }
    
    struct DEXInfo {
        address router;
        address factory;
        address weth;
    }

    struct UserInfo {
        uint debt;
        uint total;
        uint totalInvested;
    }
    ERC20 public rewardToken;
    uint256 public decimals;
    string public metadataURL;
    address public feeWallet;
    uint public feeAmount;
    bool public burnType=false;
    bool public isPoolCancel;


    ERC20 public payToken;
    uint256 public payTokenDecimals;


    FinInfo public finInfo;
    Timestamps public timestamps;
     DEXInfo public dexInfo;

 TokenLockerFactory public lockerFactory;
 
    uint256 public totalInvested;
    uint256 public tokensForDistribution;
    uint256 public distributedTokens;

    bool public distributed = false;


    mapping(address => UserInfo) public userInfo;

    
    event TokensDebt(
        address indexed holder,
        uint256 payAmount,
        uint256 tokenAmount
    );

    event TokensWithdrawn(address indexed holder, uint256 amount);
    
    
  

    constructor(
        ERC20 _rewardToken,
        ERC20 _payToken,
        FinInfo memory _finInfo,
        Timestamps memory _timestamps,
        DEXInfo memory _dexInfo,
        address _lockerFactoryAddress,
        string memory _metadataURL,
        bool _burnType,
        address _feeWallet,
        uint _feeAmount
    ) {
        rewardToken = _rewardToken;
        decimals = rewardToken.decimals();
        lockerFactory = TokenLockerFactory(_lockerFactoryAddress);
        payToken = _payToken;
        payTokenDecimals = payToken.decimals();
        burnType=_burnType;
        feeWallet=_feeWallet;
        feeAmount=_feeAmount;
        finInfo = _finInfo;
        setTimestamps(_timestamps);
        dexInfo = _dexInfo;
        setMetadataURL(_metadataURL);
    }

    function setTimestamps(Timestamps memory _timestamps) internal {
        require(
            _timestamps.startTimestamp < _timestamps.endTimestamp,
            "Start timestamp must be less than finish timestamp"
        );
        require(
            _timestamps.endTimestamp > block.timestamp,
            "Finish timestamp must be more than current block"
        );

        timestamps = _timestamps;
    }

    function setMetadataURL(string memory _metadataURL) public{
        metadataURL = _metadataURL;
    }

    function pay(uint256 amount) external {
        require(block.timestamp >= timestamps.startTimestamp, "Not started");
        require(block.timestamp < timestamps.endTimestamp, "Ended");

        require(amount >= finInfo.minPayment, "Less then min amount");
        require(amount <= finInfo.maxPayment, "More then max amount");
        require(totalInvested.add(amount) <= finInfo.hardCap, "Overfilled");

        UserInfo storage user = userInfo[msg.sender];
        require(user.totalInvested.add(amount) <= finInfo.maxPayment, "More then max amount");
        // @to-do - check allowance

        uint256 tokenAmount = getTokenAmount(amount, finInfo.tokenPrice);

        payToken.safeTransferFrom(msg.sender, address(this), amount);

        totalInvested = totalInvested.add(amount);
        tokensForDistribution = tokensForDistribution.add(tokenAmount);
        user.totalInvested = user.totalInvested.add(amount);
        user.total = user.total.add(tokenAmount);
        user.debt = user.debt.add(tokenAmount);

        emit TokensDebt(msg.sender, amount, tokenAmount);
    }

    function refund() external {
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        require(totalInvested < finInfo.softCap, "The IDO pool has reach soft cap.");

        UserInfo storage user = userInfo[msg.sender];

        uint256 _amount = user.totalInvested;
        require(_amount > 0 , "You have no investment.");

        user.debt = 0;
        user.totalInvested = 0;
        user.total = 0;

        payToken.safeTransfer(msg.sender, _amount);
    }

    /// @dev Allows to claim tokens for the specific user.
    /// @param _user Token receiver.
    function claimFor(address _user) external {
        proccessClaim(_user);
    }

    /// @dev Allows to claim tokens for themselves.
    function claim() external {
        proccessClaim(msg.sender);
    }

    /// @dev Proccess the claim.
    /// @param _receiver Token receiver.
    function proccessClaim(
        address _receiver
    ) internal nonReentrant{
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        UserInfo storage user = userInfo[_receiver];

        uint256 _amount = user.debt;
        require(_amount > 0 , "You do not have debt tokens.");

        user.debt = 0;
        distributedTokens = distributedTokens.add(_amount);
        rewardToken.safeTransfer(_receiver, _amount);
        emit TokensWithdrawn(_receiver,_amount);
    }


    function getNotSoldToken() public view returns(uint256){
        uint256 balance = rewardToken.balanceOf(address(this));
        return balance.add(distributedTokens).sub(tokensForDistribution);
    }

    function refundTokens() external onlyOwner {
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        require(totalInvested < finInfo.softCap, "The IDO pool has reach soft cap.");

        uint256 balance = rewardToken.balanceOf(address(this));
        require(balance > 0, "The IDO pool has not refund tokens.");
        rewardToken.safeTransfer(msg.sender, balance);
    }


 function Finalize() external payable onlyOwner {
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        require(totalInvested >= finInfo.softCap, "The IDO pool did not reach soft cap.");
        require(!distributed, "Already distributed.");

        // This forwards all available gas. Be sure to check the return value!
        // Detect Fee Amount  and Transfer
        uint256 platformFee = totalInvested.mul(feeAmount).div(10000); // 10000 for basis points
        totalInvested = totalInvested.sub(platformFee);

    //    Send Platform Fee To FeeWallet
          
        bool success=  payToken.transfer(feeWallet,platformFee);
        require(success,'transfer Failed');

        uint256 UnSoldToken = getNotSoldToken();
        if(burnType){
           // Burn unsold tokens by sending to the burn address
         rewardToken.safeTransfer(0x000000000000000000000000000000000000dEaD, UnSoldToken);
        }
        else{
          // Ensure there are unsold tokens before withdrawing
        require(UnSoldToken > 0, "The IDO pool has not unsold tokens.");
        rewardToken.safeTransfer(msg.sender, UnSoldToken);      
          }

        uint256 balance = payToken.balanceOf(address(this));
         require(balance>0,"Not Enough Fund ");
        if ( finInfo.lpInterestRate > 0 && finInfo.listingPrice > 0 ) {
         
            uint256 payTokenForLp = (balance * finInfo.lpInterestRate)/100;
            uint256 payTokenWithdraw = balance - payTokenForLp;

            uint256 RewardtokenAmount = getTokenAmount(payTokenForLp, finInfo.listingPrice);

            // Add Liquidity Token 
            // IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(dexInfo.router);
            // rewardToken.approve(address(uniswapRouter), tokenAmount);
            // (,, uint liquidity) = uniswapRouter.addLiquidityETH{value: ethForLP}(
            //     address(rewardToken),
            //     tokenAmount,
            //     0, // slippage is unavoidable
            //     0, // slippage is unavoidable
            //     address(this),
            //     block.timestamp + 360
            // );
            IUniswapV2Router02 uniswapRouter=IUniswapV2Router02(dexInfo.router);
            rewardToken.approve(address(uniswapRouter),RewardtokenAmount);
            payToken.approve(address(uniswapRouter),payTokenForLp);
          (,,uint liquidity)=uniswapRouter.addLiquidity(
            address(rewardToken) ,
            address(payToken), 
            RewardtokenAmount,
             payTokenForLp,
              0,
              0,
              address(this),
              block.timestamp + timestamps.unlockTimestamp
               );

            // Lock LP Tokens
            (address lpTokenAddress) = IUniswapV2Factory(dexInfo.factory).getPair(address(rewardToken), address(payToken));

            ERC20 lpToken = ERC20(lpTokenAddress);

            if (timestamps.unlockTimestamp > block.timestamp) {
                lpToken.approve(address(lockerFactory), liquidity);
                lockerFactory.createLocker{value: msg.value}(
                    lpToken,
                    string.concat(lpToken.symbol(), " tokens locker"),
                    liquidity, msg.sender, timestamps.unlockTimestamp
                );
            } else {
                lpToken.transfer(msg.sender, liquidity);
                // return msg.value along with eth to output if someone sent it wrong
                
            }

            // Withdraw rest Token
            (bool transferSuccess ) = payToken.transfer(msg.sender,payTokenWithdraw);
              require(success, "Transfer failed.");
        } else {         
            (bool transferSuccess) =payToken.transfer(msg.sender,balance);
            require(success, "Transfer failed.");
        }

        distributed = true;
    }

    function getTokenAmount(uint256 payTokenAmount, uint256 RewardToken)
        internal
        view
        returns (uint256)
    {
        return (payTokenAmount / RewardToken) * 10**decimals;
    }
    /**
     * @notice It allows the owner to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw with the exception of rewardToken
     * @param _tokenAmount: the number of token amount to withdraw
     * @dev Only callable by owner.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(rewardToken));
        ERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
    }
}