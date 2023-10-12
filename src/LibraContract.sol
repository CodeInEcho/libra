// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "forge-std/console.sol";
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
        uint256 price;
        address seller;
        uint256 amount;
        uint256 payTime;
        uint256 quantity;
        uint256 feesRatio;
        uint256 collateral;
        OrderStatus state;
    }

    struct OrderParams {
        string id;
        address buyer;
        uint256 price;
        address seller;
        uint256 quantity;
        uint256 feesRatio;
        uint256 collateral;
    }

    mapping(string => Order) public orders;
    mapping(string => uint) public deposits;
    // Track status of each order (validated, cancelled, and fraction filled).
    mapping(string => OrderStatus) private _orderStatus;

    constructor() {
        admin = msg.sender;
    }

    function createOrder(OrderParams memory params, bytes memory signature) public payable {
        require(msg.sender == params.buyer, "Invalid buyer");

        // Check if msg.value is equal to totalPrice
        uint256 totalPrice = params.quantity * params.price + params.collateral;
        require(msg.value == totalPrice, "Value sent is not correct");

        bytes32 hashedParams = keccak256(
            abi.encodePacked(params.id, params.buyer, params.seller, params.price, params.quantity)
        );
        // bytes32 ethSignedMessageHash = getEthSignedMessageHash(hashedParams);
        address recovered = ECDSA.recover(hashedParams, signature);
        if (recovered != signer) revert InvalidSignature();

        uint256 payTime = block.timestamp;

        orders[params.id] = Order({
            id: params.id,
            payTime: payTime,
            buyer: params.buyer,
            price: params.price,
            seller: params.seller,
            state: OrderStatus.Paid,
            quantity: params.quantity,
            feesRatio: params.feesRatio,
            collateral: params.collateral,
            amount: params.quantity * params.price
        });
    }

    function confirmDeliver(string memory id, bytes memory signature) public {
        Order memory order = orders[id];
        require(msg.sender == order.seller, "Invalid seller");
        require(order.state == OrderStatus.Paid, "Invalid state");
        
        bytes32 hashedParams = keccak256(abi.encodePacked(id));
        address recovered = ECDSA.recover(hashedParams, signature);
        if (recovered != signer) revert InvalidSignature();

        order.state = OrderStatus.Shipped;
        orders[id] = order;
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

    // function getOrderStatus(string memory id) public view returns(OrderStatus) {
    //     return orders[id].status;
    // }

    function cancelOrder(uint id) public {}

    function shipOrder(uint id) public {}
}
