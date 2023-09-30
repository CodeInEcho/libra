// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "forge-std/console.sol";
// import { Ownable } from "openzeppelin/contracts/access/Ownable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LibraContract {
    // using ECDSA for bytes32;
    address public admin;
    address public signer;

    error InvalidSignature();

    enum OrderStatus {Paid, Shipped, Completed, Cancelled}

    struct Order {
        string id;
        address buyer;
        address seller;
        uint256 amount;
        uint256 price;
        uint256 quantity;
        uint256 payTime;
        uint256 feesRatio;
        uint256 collateral;
        OrderStatus state;
    }

    mapping(string => Order) public orders;
    mapping(string => uint) public deposits;
    // Track status of each order (validated, cancelled, and fraction filled).
    mapping(string => OrderStatus) private _orderStatus;

    constructor() {
        admin = msg.sender;
    }

    function createOrder(string memory id, address buyer, address seller, uint256 price, uint256 quantity, 
    uint256 collateral, uint256 feesRatio, bytes memory signature) public payable {
        require(msg.sender == buyer, "Invalid buyer");

        // Check if msg.value is equal to totalPrice
        uint256 totalPrice = quantity * price + collateral;
        require(msg.value == totalPrice, "Value sent is not correct");

        bytes32 hashedParams = keccak256(
            abi.encodePacked(id, buyer, seller, price, quantity)
        );
        // bytes32 ethSignedMessageHash = getEthSignedMessageHash(hashedParams);
        address recovered = ECDSA.recover(hashedParams, signature);
        if (recovered != signer) revert InvalidSignature();
        console.logAddress(recovered);

        uint256 payTime = block.timestamp;

        orders[id] = Order({
            id: id,
            buyer: buyer,
            seller: seller,
            price: price,
            amount: quantity * price,
            payTime: payTime,
            quantity: quantity,
            feesRatio: feesRatio,
            collateral: collateral,
            state: OrderStatus.Paid
        });
    }

    function getEthSignedMessageHash(
        bytes32 _messageHash
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
            );
    }

    function setSigner(address _signer) public {
        signer = _signer;
    }

    function getOrder(string memory id) public view returns(Order memory) {
        return orders[id];
    }

    function getOrderId(string memory id) public view returns(string memory) {
        return orders[id].id;
    }

    function getOrderBuyer(string memory id) public view returns(address) {
        return orders[id].buyer;
    }

    function getOrderStatus(string memory id) public view returns(OrderStatus) {
        return orders[id].status;
    }

    function cancelOrder(uint id) public {}

    function shipOrder(uint id) public {}
}
