// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "forge-std/console.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LibraContract {
    // using ECDSA for bytes32;
    address public admin;
    address public signer;
    address private usdc;
    address private usdt;

    error InvalidSignature();

    enum OrderStatus {Paid, Shipped, Completed, Finished, Cancelled}

    struct Order {
        string id;
        address buyer;
        uint256 price;
        address seller;
        uint256 amount;
        uint256 payTime;
        uint256 quantity;
        uint256 feesRatio;
        uint256 completeTime;
        uint256 securityDeposit;
        uint256 fundReleasePeriod;
        OrderStatus state;
    }

    struct OrderParams {
        string id;
        address buyer;
        uint256 price;
        address seller;
        uint256 quantity;
        uint256 feesRatio;
        uint256 securityDeposit;
        uint256 fundReleasePeriod;
    }

    struct Account {
        uint balance;
        uint frozenBalance;
        uint securityDeposit;
        uint frozenSecurityDeposit;
    }

    mapping(string => Order) public orders;
    // mapping(address => uint256) public balance;
    mapping(string => uint256) public deposits;
    mapping(address => Account) public accounts;
    // Track status of each order (validated, cancelled, and fraction filled).
    mapping(string => OrderStatus) private _orderStatus;

    constructor() {
        usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        admin = msg.sender;
    }

    function createOrder(OrderParams memory params, bytes memory signature) public payable {
        require(msg.sender == params.buyer, "Invalid buyer");

        // Check if msg.value is equal to totalPrice
        uint256 amount = params.quantity * params.price;
        uint256 totalPrice = amount + amount * params.feesRatio / 100 / 2 + params.securityDeposit;
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
            completeTime: 0,
            amount: amount,
            payTime: payTime,
            buyer: params.buyer,
            price: params.price,
            seller: params.seller,
            state: OrderStatus.Paid,
            quantity: params.quantity,
            feesRatio: params.feesRatio,
            securityDeposit: params.securityDeposit,
            fundReleasePeriod: params.fundReleasePeriod
        });
    }

    function confirmDeliver(string memory id, bytes memory signature) public {
        Order memory order = orders[id];
        require(msg.sender == order.seller, "Invalid seller");
        require(order.state == OrderStatus.Paid, "Invalid state");

        uint securityBalance = accounts[order.seller].securityDeposit - accounts[order.seller].frozenSecurityDeposit;
        uint needSecurityDeposit = order.securityDeposit * order.quantity;
        require(securityBalance >= needSecurityDeposit, "Insufficient security deposit");

        accounts[order.seller].frozenSecurityDeposit += allSecurityDeposit;

        bytes32 hashedParams = keccak256(abi.encodePacked(id));
        address recovered = ECDSA.recover(hashedParams, signature);
        if (recovered != signer) revert InvalidSignature();

        order.state = OrderStatus.Shipped;
        orders[id] = order;
    }

    function confirmReceipt(string memory id, bytes memory signature) public {
        Order memory order = orders[id];
        require(msg.sender == order.seller, "Invalid seller");
        require(order.state == OrderStatus.Shipped, "Invalid state");

        bytes32 hashedParams = keccak256(abi.encodePacked(id));
        address recovered = ECDSA.recover(hashedParams, signature);
        if (recovered != signer) revert InvalidSignature();

        balance[order.seller] += order.amount - order.amount * order.feesRatio / 100 / 2 + order.securityDeposit;

        order.state = OrderStatus.Completed;
        orders[id] = order;
    }

    // Disallow reentrancy attacks
    function withdrawById(string memory id, bytes memory signature) external payable {
        Order memory order = orders[id];
        require(msg.sender == order.seller, "Invalid seller");
        require(order.state == OrderStatus.Completed, "Invalid state");

        uint releaseTime = order.completeTime + order.fundReleasePeriod * 1 days;
        require(releaseTime >= block.timestamp, "Funds are frozen");

        bytes32 hashedParams = keccak256(abi.encodePacked(id));
        address recovered = ECDSA.recover(hashedParams, signature);
        if (recovered != signer) revert InvalidSignature();

        order.state = OrderStatus.Finished;
        orders[id] = order;

        uint256 amount = order.amount - order.amount * order.feesRatio / 2 + order.securityDeposit;
        balance[order.seller] -= amount;

        payable(msg.sender).transfer(amount);
    }

    function depositSecurity() public payable {
        require(msg.value > 0, "deposit amount must be greater than 0");
        accounts[msg.sender].securityDeposit += msg.value;
    }

    function withdrawSecurity(uint amount) public payable {
        uint securityBalance = accounts[msg.sender].securityDeposit - accounts[msg.sender].frozenSecurityDeposit;
        require(amount <= securityBalance, "Insufficient security deposit");
        accounts[msg.sender].securityDeposit -= amount;
        payable(msg.sender).transfer(amount);
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

    // function getOrderStatus(string memory id) public view returns(string memory) {
    //     return orders[id].status;
    // }

    function cancelOrder(uint id) public {}

    function shipOrder(uint id) public {}
}
