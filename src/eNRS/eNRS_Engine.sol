// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {eNRS} from "./eNRS.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract eNRS_Engine is ReentrancyGuard {

    // ERRORS
    error eNRS_Engine_NeedsMoreThanZero();
    error eNRS_Engine_TokenAddressesAndPriceFeedAddressesMismatch();
    error eNRS_Engine_Token_NOT_ALLOWED();
    error eNRS_Engine_TransferFailed();
    error eNRS_Engine_BreaksHealthFactor(uint256);
    error eNRS_Engine_MintFailed();
    error eNRS_Engine_HealthFactorOKAY();
    error eNRS_Engine_HealthFactorNotImproved();

    // Events

    event CollateralDeposited(address, address, uint256);
    event CollateralRedeemed(address indexed redeemedFrom,address indexed RedeemedTo,uint256 amount );
    event mintedeNRS(address indexed account, uint256 amount);
    event burnedeNRS(address indexed account, uint256 amount);


    eNRS private immutable enrs;

    address private s_CollateralToken;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% OVERCOLLATERALIZED
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS=10;//10% BONUS
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEE_PRECISION = 1e10;

    address private s_PriceFeed;
    mapping(address user => uint256 amountCollateral) private s_collateralDeposited;
    mapping(address user => uint256 amounteNRSMinted) private s_eNRSMinted;

    constructor(address _enrs, address priceFeed) {
        enrs = eNRS(_enrs);
        s_PriceFeed = priceFeed;
    }

    function depositCollateralAndMinteNRS(uint256 amountToMint) external payable nonReentrant {
        depositCollateral();
        minteNRS(amountToMint);  
    }

    function depositCollateral() public payable nonReentrant {
        uint256 amount = msg.value;
        require(amount > 0, "eNRS_Engine_NeedsMoreThanZero");
        // require(msg.value == amount, "Amount Not same to msg.value");
        s_collateralDeposited[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, address(this), amount);
    }

    function redeemCollateral(uint256 amount) public nonReentrant {
        _redeemCollateral(amount,msg.sender,msg.sender);
        // _revertIfHealthFactorIsBroken(msg.sender);
    }


    function _redeemCollateral(uint256 amount,address _from,address _to) internal nonReentrant {
        require(amount > 0, "eNRS_Engine_NeedsMoreThanZero");
        // require(s_collateralDeposited[msg.sender] >= amount, "eNRS_Engine_NotEnoughCollateral");
        s_collateralDeposited[_from] -= amount;
        //  payable(_to).transfer(amount);
        (bool success,) = _to.call{value:amount}("");
        if(!success) {
            revert("eNRS_Engine_RedeemFailed");
        }
        emit CollateralRedeemed(_from,_to, amount);        
    }
    function redeemCollateralForeNRS( uint256 amountCollateral, uint256 amounteNRStoBurn) public {
        burneNRS(amounteNRStoBurn);
        redeemCollateral(amountCollateral);
        // Already checcks health factor
    }


    function liquidate(address user,uint256 debtToCover) external nonReentrant {

        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor>=MIN_HEALTH_FACTOR){
            revert eNRS_Engine_HealthFactorOKAY();
        }


        uint256 tokenAmountFromDebtCovered = getTokenAmountFromNRS(debtToCover);

         uint256 bonusCollateral =(tokenAmountFromDebtCovered* LIQUIDATION_BONUS)/LIQUIDATION_PRECISION;
        uint256 totalCollateralToReedem = tokenAmountFromDebtCovered +bonusCollateral;

        _redeemCollateral(totalCollateralToReedem,user,msg.sender);

        // To Burn

        _burneNRS(debtToCover,user,msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);

        if(endingUserHealthFactor<=startingUserHealthFactor){
            revert eNRS_Engine_HealthFactorNotImproved();
        }
        // _revertIfHealthFactorIsBroken(msg.sender);
        emit CollateralRedeemed(user,msg.sender,totalCollateralToReedem);
    }






    function minteNRS(uint256 _amountToMint) public nonReentrant returns (bool) {
        s_eNRSMinted[msg.sender] += _amountToMint;
        // _revertIfHealthFactorIsBroken(msg.sender); // @audit 
        bool minted = enrs.mint(msg.sender,_amountToMint);
        if(!minted){
            revert eNRS_Engine_MintFailed();
        }
        return minted;
        // emit minted(msg.sender,_amountToMint);
    }

    function burneNRS(uint256 amount) public{
     _burneNRS(amount,msg.sender,msg.sender);
    // _revertIfHealthFactorIsBroken(msg.sender);
    emit burnedeNRS(msg.sender,amount);
    }

    function _burneNRS(uint256 amountToBurn,address onBehalf, address eNRSFrom ) private {

          s_eNRSMinted[onBehalf] -= amountToBurn;
        bool success = enrs.transferFrom(eNRSFrom,address(this),amountToBurn);
        if(!success){
            revert eNRS_Engine_TransferFailed();
        }
        enrs.burn(amountToBurn);
        // 

    }



    function getNRSValue( uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_PriceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEE_PRECISION ) * amount *133) / (PRECISION); // Additional Fee Precision * Precision
    }

      function getTokenAmountFromNRS( uint256 USDAmountinWei)public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_PriceFeed);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return (USDAmountinWei)*1e18 /(uint256(price)*1e10*133);
        }

    function _healthFactor(address user) public view returns (uint256) {
        // To get Collateral Value

        
        (uint256 totaleNRSMinted, uint256 collateralValueInNRS) = _getAccountInfo(user);

        if(totaleNRSMinted ==0){
            return type(uint256).max;
        }
        uint256 collateralAdjustedThreshold = (collateralValueInNRS* LIQUIDATION_THRESHOLD)/LIQUIDATION_PRECISION;
        return ((collateralAdjustedThreshold * PRECISION )/ totaleNRSMinted);        
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // Check Health Factor
        // Revert IF they dont have enough

        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < 1e18){
            revert eNRS_Engine_BreaksHealthFactor(userHealthFactor);
        }


    }

      function _getAccountInfo(address user) private view returns (uint256 totaleNRSMinted, uint256 collateralValueInNRS) {
        totaleNRSMinted = s_eNRSMinted[user];
        collateralValueInNRS = getAccountCollateralValue(user);
    }

    function getAccountInfo(address user) public view returns (uint256 totaleNRSMinted, uint256 collateralValueInNRS) {
        (totaleNRSMinted, collateralValueInNRS) = _getAccountInfo(user);
        
    }

    function getCollateralBalanceOfUser(address user) public view returns (uint256) {
        return s_collateralDeposited[user];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInNRS) {
    uint256 amount = s_collateralDeposited[user];
    totalCollateralValueInNRS = getNRSValue( amount);
    return totalCollateralValueInNRS;
    }

   receive() external payable {
        depositCollateral();
    }

//     fallback() external payable {
//         depositCollateral();
//    }


}