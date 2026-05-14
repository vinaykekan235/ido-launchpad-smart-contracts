// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./IDOPool.sol";
import "./IDOERC20Pool.sol";

contract IDOFactory is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20Burnable;
    using SafeERC20 for ERC20;

    ERC20Burnable public feeToken;
    address public feeWallet;
    uint256 public feeAmount;
   
    address[] public idoPools; //to Storing the all pool data 
    mapping (address => bool) public idoPoolsMap;


    event IDOCreated(
        address indexed owner,
        address idoPool,
        address indexed rewardToken,
        string tokenURI
    );

    event TokenFeeUpdated(address newFeeToken);
    event FeeAmountUpdated(uint256 newFeeAmount);
    event FeeWalletUpdated(address newFeeWallet);

    constructor(
        ERC20Burnable _feeToken,
        uint256 _feeAmount,
        uint256 _burnPercent
    ){
        feeToken = _feeToken;
        feeAmount = _feeAmount;
    
    }

    function isIdoAddress(address _address) public view returns (bool) {
        return idoPoolsMap[_address];
    } 

    function getIdoPools() public view returns (address[] memory) {
      return idoPools;
    }

    function setFeeAmount(uint256 _newFeeAmount) external onlyOwner {
        feeAmount = _newFeeAmount;

        emit FeeAmountUpdated(_newFeeAmount);
    }
    
    function setFeeWallet(address _newFeeWallet) external onlyOwner {
        feeWallet = _newFeeWallet;

        emit FeeWalletUpdated(_newFeeWallet);
    }

 
//for Native  token 
    function createIDO(
        ERC20 _rewardToken,
        IDOPool.FinInfo memory _finInfo,
        IDOPool.Timestamps memory _timestamps,
        IDOPool.DEXInfo memory _dexInfo,
        address _lockerFactoryAddress,
        string memory _metadataURL,
        bool _burnType
    ) external {
        IDOPool idoPool =
            new IDOPool(
                _rewardToken,
                _finInfo,
                _timestamps,
                _dexInfo,
                _lockerFactoryAddress,
                _metadataURL,
                _burnType,
                feeWallet,
                feeAmount
            );
       idoPool.transferOwnership(msg.sender);
        uint8 tokenDecimals = _rewardToken.decimals();

        uint256 transferAmount = getTokenAmount(_finInfo.hardCap, _finInfo.tokenPrice, tokenDecimals);

        if (_finInfo.lpInterestRate > feeAmount && _finInfo.listingPrice > 0) {
            transferAmount += getTokenAmount(_finInfo.hardCap * _finInfo.lpInterestRate / 100, _finInfo.listingPrice, tokenDecimals);
        }

       processIDOCreate(
            transferAmount,
            _rewardToken,
            address(idoPool),
            _metadataURL
        );     
    }
    // for Erc-20 Token 

    function createIDOERC20(
        ERC20 _rewardToken,
        ERC20 _payToken,
        IDOERC20Pool.FinInfo memory _finInfo,
        IDOERC20Pool.Timestamps memory _timestamps,
        IDOERC20Pool.DEXInfo memory _dexInfo,
         address _lockerFactoryAddress,
        string memory _metadataURL,
        bool _burnType
    ) external {
      
        IDOERC20Pool idoPool =
            new IDOERC20Pool(
                _rewardToken,
                _payToken,
                _finInfo,
                _timestamps,
                _dexInfo,
                _lockerFactoryAddress,
                _metadataURL,
                 _burnType,
                 feeWallet,
                 feeAmount
            );
        uint8 rewardTokenDecimals = _rewardToken.decimals();
        uint256 transferAmount = getTokenAmount(_finInfo.hardCap, _finInfo.tokenPrice, rewardTokenDecimals);

      if (_finInfo.lpInterestRate > feeAmount && _finInfo.listingPrice > 0) {
            transferAmount += getTokenAmount(_finInfo.hardCap * _finInfo.lpInterestRate / 100, _finInfo.listingPrice, rewardTokenDecimals);
        }
        idoPool.transferOwnership(msg.sender);

        processIDOCreate(
            transferAmount,
            _rewardToken,
            address(idoPool),
            _metadataURL
        );
    }

    function processIDOCreate(
        uint256 transferAmount,
        ERC20 _rewardToken,
        address idoPoolAddress,
        string memory _metadataURL
    ) private {

        _rewardToken.safeTransferFrom(
            msg.sender,
            idoPoolAddress,
            transferAmount
        );
        
        idoPools.push(idoPoolAddress);

        emit IDOCreated(
            msg.sender,
            idoPoolAddress,
            address(_rewardToken),
            _metadataURL
        );
    }

    function getTokenAmount(uint256 ethAmount, uint256 oneTokenInWei, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        return (ethAmount / oneTokenInWei) * 10**decimals;
    }
    function isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

}