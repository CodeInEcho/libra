// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "forge-std/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LibraContract is Ownable, ReentrancyGuard {
    // using ECDSA for bytes32;
    address public admin;
    address public signer;

    error InvalidSignature();

    enum OrderStatus {Paid, Shipped, HoldForFunds, Completed, Finished, Cancelled}

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
    mapping(string orderId => Order order) public orders;
    mapping(address wallet => Account account) public accounts;

    constructor(address initialOwner) Ownable(initialOwner) {
        admin = msg.sender;
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
        require(msg.sender == order.buyer, "Invalid buyer");
        require(order.state == OrderStatus.Shipped, "Invalid state");

        bytes32 hashedParams = keccak256(abi.encodePacked(id));
        address recovered = ECDSA.recover(hashedParams, signature);
        if (recovered != signer) revert InvalidSignature();

        uint needSecurityDeposit = order.securityDeposit * order.quantity;
        accounts[order.seller].frozenSecurityDeposit -= needSecurityDeposit;

        uint256 totalPrice = order.amount + order.amount * order.feesRatio / 100 / 2;
        accounts[order.seller].balance += order.amount;
        accounts[order.buyer].balance -= totalPrice;
        accounts[order.buyer].frozenBalance -= totalPrice;
        uint releaseTime = block.timestamp + order.fundReleasePeriod * 1 days;
        order.completeTime = block.timestamp;

        if (releaseTime > block.timestamp) {
            accounts[order.seller].frozenBalance += order.amount;
            order.state = OrderStatus.HoldForFunds;
        } else {
            order.state = OrderStatus.Completed;
        }
        orders[id] = order;
    }

    function withdraw() external payable nonReentrant {
        releaseFunds(msg.sender);
        uint256 balance = accounts[msg.sender].balance - accounts[msg.sender].frozenBalance;
        require(balance >= 0, "Insufficient balance");
        accounts[msg.sender].balance -= balance;

        payable(msg.sender).transfer(balance);
    }

    function releaseFunds(address seller) public {
        uint256 amount = 0;
        uint256 length = orderIds.length;
        for (uint256 i = 0; i < length; i++) {
            Order memory order = orders[orderIds[i]];
            if (order.seller == seller && order.state == OrderStatus.HoldForFunds) {
                uint256 releaseTime = order.completeTime + order.fundReleasePeriod * 1 days;
                if (releaseTime <= block.timestamp) {
                    amount += order.amount;
                    order.state = OrderStatus.Completed;
                    orders[orderIds[i]] = order;
                }
            }
        }
        accounts[seller].frozenBalance -= amount;
    }

    function depositSecurity() public payable {
        require(msg.value > 0, "deposit amount must be greater than 0");
        accounts[msg.sender].securityDeposit += msg.value;
    }

    function withdrawSecurity(uint256 amount) public payable nonReentrant {
        uint securityBalance = accounts[msg.sender].securityDeposit - accounts[msg.sender].frozenSecurityDeposit;
        require(amount <= securityBalance, "Insufficient security deposit");
        accounts[msg.sender].securityDeposit -= amount;
        payable(msg.sender).transfer(amount);
    }

    function cancelOrder(string memory id) public onlyOwner {
        Order memory order = orders[id];
        order.state = OrderStatus.Cancelled;
        orders[id] = order;
    }

    function setSigner(address _signer) public onlyOwner {
        signer = _signer;
    }

    function getOrder(string memory id) public view returns(Order memory) {
        return orders[id];
    }

    function getAccount(address accountAddress) public view returns(Account memory) {
        return accounts[accountAddress];
    }
}
