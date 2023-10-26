// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "forge-std/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LibraContract is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    address public admin;
    address public signer;

    error InvalidSignature();

    event EventCreateOrder(string orderId);
    event EventConfirmDeliver(string orderId);
    event EventConfirmReceipt(string orderId);
    event EventWithdraw(uint256 amount);
    event EventDepositSecurity(uint256 amount);
    event EventwithdrawSecurity(uint256 amount);
    event EventCancelOrder(string orderId);

    enum OrderStatus {Paid, Shipped, HoldForFunds, Completed, Finished, Cancelled}

    struct Order {
        string id;
        uint256 price;
        address buyer;
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
        uint256 price;
        address buyer;
        address seller;
        uint256 quantity;
        uint256 feesRatio;
        uint256 securityDeposit;
        uint256 fundReleasePeriod;
    }

    struct EIP712Domain {
        string  name;
        string  version;
        uint256 chainId;
        address verifyingContract;
    }

    struct Account {
        uint balance;
        uint frozenBalance;
        uint securityDeposit;
        uint frozenSecurityDeposit;
    }

    bytes32 public immutable DOMAIN_SEPARATOR;

    mapping(string orderId => Order order) public orders;
    mapping(address wallet => Account account) public accounts;
    mapping(address wallet => string[] orderIds) public freezeOrderIds;

    // USDT contract address
    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7; 
    // USDC contract address
    address public constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;


    bytes32 public constant EIP712DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 internal constant TYPE_HASH = keccak256(
        "OrderParams(string id, uint256 price, address buyer, "
        "address seller, uint256 quantity, "
        "uint256 feesRatio, uint256 securityDeposit, uint256 fundReleasePeriod)"
    );

    constructor(address initialOwner) Ownable() {
        admin = initialOwner;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256("Libra"),
                keccak256("v0.0.1"),
                block.chainid,
                address(this)
            )
        );
    }

    function getStructHash(OrderParams memory orderInfo) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TYPE_HASH,
                keccak256(bytes(orderInfo.id)),
                orderInfo.price,
                orderInfo.buyer,
                orderInfo.seller,
                orderInfo.quantity,
                orderInfo.feesRatio,
                orderInfo.securityDeposit,
                orderInfo.fundReleasePeriod
            )
        );
    }

    function getTypedDataHash(OrderParams memory orderInfo) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            getStructHash(orderInfo)
        ));
    }

    function verify(OrderParams memory orderInfo, uint8 v, bytes32 r, bytes32 s)
    public view returns (bool) {
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            getStructHash(orderInfo)
        ));
        return ecrecover(digest, v, r, s) == signer;
    }

    function createOrder(OrderParams memory orderInfo, bytes memory signature) public payable {
        require(msg.sender == orderInfo.buyer, "Invalid buyer");

        uint256 amount = orderInfo.quantity * orderInfo.price;
        uint256 totalPrice = amount + amount * orderInfo.feesRatio / 100 / 2;
        require(msg.value == totalPrice, "Value sent is not correct");

        bytes32 hashedParams = keccak256(abi.encodePacked(orderInfo.id));
        bytes32 signedHash = ECDSA.toEthSignedMessageHash(hashedParams);
        address recovered = ECDSA.recover(signedHash, signature);
        if (recovered != signer) revert InvalidSignature();

        accounts[orderInfo.buyer].balance += totalPrice;
        accounts[orderInfo.buyer].frozenBalance += totalPrice;

        uint256 payTime = block.timestamp;

        orders[orderInfo.id] = Order({
            id: orderInfo.id,
            completeTime: 0,
            amount: amount,
            payTime: payTime,
            buyer: orderInfo.buyer,
            price: orderInfo.price,
            seller: orderInfo.seller,
            state: OrderStatus.Paid,
            quantity: orderInfo.quantity,
            feesRatio: orderInfo.feesRatio,
            securityDeposit: orderInfo.securityDeposit,
            fundReleasePeriod: orderInfo.fundReleasePeriod
        });
        if (orderInfo.fundReleasePeriod > 0) freezeOrderIds[orderInfo.seller].push(orderInfo.id);

        emit EventCreateOrder(orderInfo.id);
    }

    function confirmDeliver(string memory id, bytes memory signature) public {
        Order memory order = orders[id];
        require(bytes(order.id).length != 0, "Invalid orderId");
        require(msg.sender == order.seller, "Invalid seller");
        require(order.state == OrderStatus.Paid, "Invalid state");

        uint securityBalance = accounts[order.seller].securityDeposit - accounts[order.seller].frozenSecurityDeposit;
        uint needSecurityDeposit = order.securityDeposit * order.quantity;
        require(securityBalance >= needSecurityDeposit, "Insufficient security deposit");

        accounts[order.seller].frozenSecurityDeposit += needSecurityDeposit;

        bytes32 hashedParams = keccak256(abi.encodePacked(id));
        bytes32 signedHash = ECDSA.toEthSignedMessageHash(hashedParams);
        address recovered = ECDSA.recover(signedHash, signature);
        if (recovered != signer) revert InvalidSignature();

        order.state = OrderStatus.Shipped;
        orders[id] = order;
        
        emit EventConfirmDeliver(id);
    }

    function confirmReceipt(string memory id, bytes memory signature) public {
        Order memory order = orders[id];
        require(bytes(order.id).length != 0, "Invalid orderId");
        require(msg.sender == order.buyer, "Invalid buyer");
        require(order.state == OrderStatus.Shipped, "Invalid state");

        bytes32 hashedParams = keccak256(abi.encodePacked(id));
        bytes32 signedHash = ECDSA.toEthSignedMessageHash(hashedParams);
        address recovered = ECDSA.recover(signedHash, signature);
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

        emit EventConfirmReceipt(id);
    }

    function withdraw() external payable nonReentrant {
        releaseFunds(msg.sender);
        uint256 balance = accounts[msg.sender].balance - accounts[msg.sender].frozenBalance;
        require(balance >= 0, "Insufficient balance");
        accounts[msg.sender].balance -= balance;

        payable(msg.sender).transfer(balance);

        emit EventWithdraw(balance);
    }

    function releaseFunds(address seller) public {
        uint256 amount = 0;
        string[] memory orderIds = freezeOrderIds[seller];
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

        emit EventDepositSecurity(msg.value);
    }

    function withdrawSecurity(uint256 amount) public payable nonReentrant {
        uint securityBalance = accounts[msg.sender].securityDeposit - accounts[msg.sender].frozenSecurityDeposit;
        require(amount <= securityBalance, "Insufficient security deposit");
        accounts[msg.sender].securityDeposit -= amount;
        payable(msg.sender).transfer(amount);

        emit EventwithdrawSecurity(amount);
    }

    function cancelOrder(string memory id) public onlyOwner {
        Order memory order = orders[id];
        require(bytes(order.id).length != 0, "Invalid orderId");
        order.state = OrderStatus.Cancelled;
        orders[id] = order;

        emit EventCancelOrder(id);
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
