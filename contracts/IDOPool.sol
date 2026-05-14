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

contract IDOPool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    
    struct FinInfo {
        uint256 tokenPrice; // one token in WEI
        uint256 softCap;
        uint256 hardCap;
        uint256 minEthPayment;
        uint256 maxEthPayment;
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
        uint totalInvestedETH;
    }

    ERC20 public rewardToken;
    uint256 public decimals;
    string public metadataURL;
    address public feeWallet;
    uint public feeAmount;
    bool public burnType=false;
    bool public isPoolCancel;


    FinInfo public finInfo;
    Timestamps public timestamps;
    DEXInfo public dexInfo;

    TokenLockerFactory public lockerFactory;

    uint256 public totalInvestedETH;
    uint256 public tokensForDistribution;
    uint256 public distributedTokens;

    bool public distributed = false;

    mapping(address => UserInfo) public userInfo;

    event TokensDebt(
        address indexed holder,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    event PoolCancelled(uint256 timestamp);

    event TokensWithdrawn(address indexed holder, uint256 amount);
    constructor(
        ERC20 _rewardToken,
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
            "Start timestamp must be less    than finish timestamp"
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

    function pay() payable external {
        require(block.timestamp >= timestamps.startTimestamp, "Not started");
        require(block.timestamp < timestamps.endTimestamp, "Ended");

        require(msg.value >= finInfo.minEthPayment, "Less then min amount");
        require(msg.value <= finInfo.maxEthPayment, "More then max amount");
        require(totalInvestedETH.add(msg.value) <= finInfo.hardCap, "Overfilled");//ye condition check karna hai ki kon case me execute ho rha  hai 

        UserInfo storage user = userInfo[msg.sender];
        require(user.totalInvestedETH.add(msg.value) <= finInfo.maxEthPayment, "More then max amount");

        uint256 tokenAmount = getTokenAmount(msg.value, finInfo.tokenPrice);

        totalInvestedETH = totalInvestedETH.add(msg.value);
        tokensForDistribution = tokensForDistribution.add(tokenAmount);
        user.totalInvestedETH = user.totalInvestedETH.add(msg.value);
        user.total = user.total.add(tokenAmount);
        user.debt = user.debt.add(tokenAmount);

        emit TokensDebt(msg.sender, msg.value, tokenAmount);
    }

    function refund() external {//this function can we use for claimRefund by user
  
        require(isPoolCancel, "Pool is not canceled");
        require(userInfo[msg.sender].totalInvestedETH > 0, "No investment to refund");

        UserInfo storage user = userInfo[msg.sender];

        uint256 _amount = user.totalInvestedETH;
        require(_amount > 0 , "You have no investment.");

        user.debt = 0;
        user.totalInvestedETH = 0;
        user.total = 0;

        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed.");

    }

    /// @dev Allows to claim tokens for the specific user. //
    /// @param _user Token receiver.// this function are used to call ui to claim user token 
    function claimFor(address _user) external {
        proccessClaim(_user);
    }

    /// @dev Allows to claim tokens for themselves.
    function claim() external {//  user claim itself thier token 
        proccessClaim(msg.sender);
    }

    /// @dev Proccess the claim.
    /// @param _receiver Token receiver.
    function proccessClaim(
        address _receiver
    ) internal nonReentrant{
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        require(totalInvestedETH >= finInfo.softCap, "The IDO pool did not reach soft cap.");

        UserInfo storage user = userInfo[_receiver];

        uint256 _amount = user.debt;
        require(_amount > 0 , "You do not have debt tokens.");

        user.debt = 0;
        distributedTokens = distributedTokens.add(_amount);
        rewardToken.safeTransfer(_receiver, _amount);
        emit TokensWithdrawn(_receiver,_amount);
    }

    // Updated Code  
       function Finalize() external payable onlyOwner {
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        require(totalInvestedETH >= finInfo.softCap, "The IDO pool did not reach soft cap.");
        require(!distributed, "Already distributed.");

        // This forwards all available gas. Be sure to check the return value!
        // Detect Fee Amount  and Transfer
        uint256 platformFee = totalInvestedETH.mul(feeAmount).div(10000); // 10000 for basis points
        totalInvestedETH = totalInvestedETH.sub(platformFee);

       (bool feeTransferSuccess, ) = feeWallet.call{value: platformFee}("");
        require(feeTransferSuccess, "Platform fee transfer failed");
     
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

        uint256 balance = address(this).balance;
        require(balance>0,'Not Enough Funds in Pool');
        if ( finInfo.lpInterestRate > 0 && finInfo.listingPrice > 0 ) {
          
            uint256 ethForLP = (balance * finInfo.lpInterestRate)/100;
            uint256 ethWithdraw = balance - ethForLP;

            uint256 tokenAmount = getTokenAmount(ethForLP, finInfo.listingPrice);

            // Add Liquidity ETH
            IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(dexInfo.router);
            rewardToken.approve(address(uniswapRouter), tokenAmount);
            (,, uint liquidity) = uniswapRouter.addLiquidityETH{value: ethForLP}(
                address(rewardToken),
                tokenAmount,
                0, // slippage is unavoidable
                0, // slippage is unavoidable
                address(this),
                block.timestamp + 360
            );

            // Lock LP Tokens
            (address lpTokenAddress) = IUniswapV2Factory(dexInfo.factory).getPair(address(rewardToken), dexInfo.weth);

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
                ethWithdraw += msg.value;
            }

            // Withdraw rest ETH
            (bool success, ) = msg.sender.call{value: ethWithdraw}("");
            require(success, "Transfer failed.");
        } else {
            (bool success, ) = msg.sender.call{value: balance}("");
            require(success, "Transfer failed.");
        }

        distributed = true;
    }
 

    function getNotSoldToken() public view returns(uint256){
        uint256 balance = rewardToken.balanceOf(address(this));
        return balance.add(distributedTokens).sub(tokensForDistribution);
    }

    function refundTokens() external onlyOwner {
        // require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        // require(totalInvestedETH < finInfo.softCap, "The IDO pool has reach soft cap."); // this is for some times disble after checking proper 
        require(isPoolCancel, "Pool is not canceled");
        uint256 balance = rewardToken.balanceOf(address(this));
        require(balance > 0, "The IDO pool has not refund tokens.");
        rewardToken.safeTransfer(msg.sender, balance);
    }


    function getTokenAmount(uint256 ethAmount, uint256 oneTokenInWei)
        internal
        view
        returns (uint256)
    {
        return (ethAmount / oneTokenInWei) * 10**decimals;
    }


   function cancelSale() external onlyOwner {
    require(!isPoolCancel, "Pool already canceled");
    require(block.timestamp < timestamps.endTimestamp, "Cannot cancel after the sale ends");
    
    isPoolCancel = true;

    emit PoolCancelled(block.timestamp);
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

// Withdraw Cancelled Tokens making this name Function well soon