// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "filename";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


enum PositionType {
    LONG,
    SHORT
}
struct Position {
 PositionType positionType;
    uint256 size;
    uint256 collateral;
    uint256 entryPrice;
    bool isClosed;

}

contract perp {
    using SafeERC20 for IERC20;

    AggregatorV3Interface internal priceFeed;

    // errors
    error InsufficientCollateral(uint256 required, uint256 available);
    error PositionNotSettled();
    error PositionNotOpen();

    // state variables
    IERC20 public asset;
    uint256 public multiplier = 1e10;
    uint256 maxUtilizationPercentage = 80;
    

    mapping (address => Position) public positions;

    // modifiers
    modifier nonZeroAddress(address _address){
        require(_address != address(0), "Zero address not allowed");
        _;
    }

    constructor (address _asset, address _priceFeed) nonZeroAddress(_asset) nonZeroAddress(_priceFeed){
        asset = IERC20(_asset);
        // multiplier = _multiplier;
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function deposit(uint256 _amount) external {
        require(asset.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
    }

    function withdraw(uint256 _amount) external {
        require(asset.transfer(msg.sender, _amount), "Transfer failed");
    }

    function openPosition(uint256 _size, uint256 _collateral) external {
        require(_collateral >= _size, "Insufficient collateral");
        require((_size / _collateral) <= maxUtilizationPercentage, "Exceeds maximum utilization percentage");
        require(asset.transferFrom(msg.sender, address(this), _collateral), "Transfer failed");
        positions[msg.sender] = Position(PositionType.LONG, _size, _collateral, 0, false);
    }




    function increasePositionSize(uint256 _additionalSize, uint256 _additionalCollateral) external {
        require(_additionalCollateral >= _additionalSize, "Insufficient collateral");
        require((_additionalSize / _additionalCollateral) <= maxUtilizationPercentage, "Exceeds maximum utilization percentage");
        require(asset.transferFrom(msg.sender, address(this), _additionalCollateral), "Transfer failed");
        positions[msg.sender].size += _additionalSize;
        positions[msg.sender].collateral += _additionalCollateral;
    }
    function increasePositionCollateral(uint256 _additionalCollateral) external {
        require(asset.transferFrom(msg.sender, address(this), _additionalCollateral), "Transfer failed");
        positions[msg.sender].collateral += _additionalCollateral;
    }
    function closePosition() external {
        Position storage position = positions[msg.sender];
        require(position.isClosed, "Position not closed");
        require(position.positionType == PositionType.SHORT, "Position not short");
        require(asset.transfer(msg.sender, position.collateral), "Transfer failed");
        delete positions[msg.sender];
    }

    function getPrice() public view returns (uint256) {
        // get the latest price from the price feed
        (, int price, , ,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function getCollateralRequirement(uint256 _size) public view returns (uint256) {
        return _size * getPrice() * multiplier;
    }

}