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

    string[] private orderIds;
    mapping(string => Order) public orders;
    mapping(string => uint256) public deposits;
    mapping(address => Account) public accounts;
    // Track status of each order (validated, cancelled, and fraction filled).
    mapping(string => OrderStatus) private _orderStatus;

    constructor() {
        admin = msg.sender;
        usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    }

    function createOrder(OrderParams memory params, bytes memory signature) public payable {
        require(msg.sender == params.buyer, "Invalid buyer");

        // Check if msg.value is equal to totalPrice
        uint256 amount = params.quantity * params.price;
        uint256 totalPrice = amount + amount * params.feesRatio / 100 / 2;
        require(msg.value == totalPrice, "Value sent is not correct");

        bytes32 hashedParams = keccak256(
            abi.encodePacked(params.id, params.buyer, params.seller, params.price, params.quantity)
        );
        // bytes32 ethSignedMessageHash = getEthSignedMessageHash(hashedParams);
        address recovered = ECDSA.recover(hashedParams, signature);
        if (recovered != signer) revert InvalidSignature();

        accounts[params.buyer].balance += totalPrice;
        accounts[params.buyer].frozenBalance += totalPrice;

        uint256 payTime = block.timestamp;

        orderIds.push(params.id);
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

        accounts[order.seller].frozenSecurityDeposit += needSecurityDeposit;

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

        uint256 totalPrice = order.amount + order.amount * order.feesRatio / 100 / 2;
        accounts[order.seller].balance += order.amount;
        accounts[order.buyer].balance -= totalPrice;
        accounts[order.buyer].frozenBalance -= totalPrice;
        uint releaseTime = order.fundReleasePeriod * 1 days;
        if (releaseTime > block.timestamp) accounts[order.seller].frozenBalance += order.amount;

        uint needSecurityDeposit = order.securityDeposit * order.quantity;
        accounts[order.seller].frozenSecurityDeposit -= needSecurityDeposit;

        order.state = OrderStatus.Completed;
        orders[id] = order;
    }

    // Disallow reentrancy attacks
    function withdrawById(string memory id, bytes memory signature) external payable {
        Order memory order = orders[id];
        require(msg.sender == order.seller, "Invalid seller");
        require(order.state == OrderStatus.Completed, "Invalid state");

        uint releaseTime = order.completeTime + order.fundReleasePeriod * 1 days;
        require(releaseTime <= block.timestamp, "Funds are frozen");

        bytes32 hashedParams = keccak256(abi.encodePacked(id));
        address recovered = ECDSA.recover(hashedParams, signature);
        if (recovered != signer) revert InvalidSignature();

        order.state = OrderStatus.Finished;
        orders[id] = order;

        uint256 feesRatio = order.amount * order.feesRatio / 2 / 100;
        uint256 amount = order.amount - feesRatio;

        uint256 balance = accounts[msg.sender].balance - accounts[msg.sender].frozenBalance;
        require(balance >= 0, 'Insufficient balance');
        accounts[order.seller].balance -= balance;

        payable(msg.sender).transfer(balance);
    }

    function availableBalance(address wallet) public view returns(uint256 amount) {
        uint256 amount = 0;
        uint256 length = orderIds.length;
        for (uint256 i = 0; i < length; i++) {
            Order memory order = orders[orderIds[i]];
            if (order.seller == wallet) {
                uint256 releaseTime = order.completeTime + order.fundReleasePeriod * 1 days;
                if (releaseTime <= block.timestamp) {
                    amount += order.amount;
                }
            }
        }
        return amount;
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

    function cancelOrder(string memory id) public {
        Order memory order = orders[id];
        order.state = OrderStatus.Cancelled;
        orders[id] = order;
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

}
