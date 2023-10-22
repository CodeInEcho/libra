// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import { LibraContract } from "../src/LibraContract.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LibraContractTest is Test {
    using ECDSA for bytes32;
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

    LibraContract _libra;

    function setUp() public {
        _libra = new LibraContract(0x19A6acE647842f55F6DF65973f72bfB298398c2c);
    }

    function testCreateOrder() public {
        vm.startPrank(0x19A6acE647842f55F6DF65973f72bfB298398c2c);
        _libra.setSigner(0x19A6acE647842f55F6DF65973f72bfB298398c2c);
        vm.stopPrank();
        // 模拟下单数据
        uint quantity = 2;
        uint price = 1 ether;
        string memory id = "order1";
        address buyer = address(0xf3efBad1f23b25B0941Ba114f0f185718BaE0375);
        address seller = address(0x19A6acE647842f55F6DF65973f72bfB298398c2c);

        // 模拟签名
        uint256 privateKey = 0x4208f1cfd43f87cad512ee1163b8f96f13e631174619f6ad81b7acc4298444b2;

        bytes32 hashed = keccak256(abi.encodePacked(id, buyer, seller, price, quantity));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashed);
        bytes memory signature = abi.encodePacked(r, s, v);
        // 下单
        LibraContract.OrderParams memory params = LibraContract.OrderParams({
            id: id,
            buyer: buyer,
            price: price,
            seller: seller,
            feesRatio: 2,
            quantity: quantity,
            securityDeposit: 1000,
            fundReleasePeriod: 7
        });
        vm.startPrank(buyer);
        vm.deal(buyer, price * quantity + 1000 + (price * quantity / 100));
        _libra.createOrder{value: price * quantity + (price * quantity / 100)}(params, signature);
        vm.stopPrank();

        LibraContract.Order memory order = _libra.getOrder(id);
        assertEq(order.buyer, buyer);
    }

    function testConfirmDeliver() public {
        testCreateOrder();
        string memory id = "order1";
        // 模拟签名
        uint256 privateKey = 0x4208f1cfd43f87cad512ee1163b8f96f13e631174619f6ad81b7acc4298444b2;

        bytes32 hashed = keccak256(abi.encodePacked(id));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashed);
        bytes memory signature = abi.encodePacked(r, s, v);
        address seller = address(0x19A6acE647842f55F6DF65973f72bfB298398c2c);
        vm.startPrank(seller);
        vm.deal(seller, 2000);
        _libra.depositSecurity{value: 2000}();
        _libra.confirmDeliver(id, signature);
        vm.stopPrank();
    }

    function testConfirmReceipt() public {
        testConfirmDeliver();
        string memory id = "order1";
        // 模拟签名
        uint256 privateKey = 0x4208f1cfd43f87cad512ee1163b8f96f13e631174619f6ad81b7acc4298444b2;

        bytes32 hashed = keccak256(abi.encodePacked(id));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashed);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(0xf3efBad1f23b25B0941Ba114f0f185718BaE0375);
        _libra.confirmReceipt(id, signature);
        vm.stopPrank();
        
        vm.startPrank(0x19A6acE647842f55F6DF65973f72bfB298398c2c);
        _libra.withdrawSecurity(2000);
        vm.stopPrank();
    }

    function testWithdraw() public {
        testConfirmReceipt();
        address seller = address(0x19A6acE647842f55F6DF65973f72bfB298398c2c);
        vm.startPrank(seller);
        vm.warp(1682807600);
        _libra.withdraw();
        vm.stopPrank();
    }

    function testCancelOrder() public {
        testWithdraw();
        vm.startPrank(0x19A6acE647842f55F6DF65973f72bfB298398c2c);
        _libra.cancelOrder("order1");
        vm.stopPrank();
    }

    // function testSign() public {
    //     // 模拟签名
    //     uint256 privateKey = 0x97ed4950eeb00f0644845197ed8bf389eea9e1b718865095861aff22c9f84ee4;

    //     // 模拟下单数据
    //     uint price = 100;
    //     uint quantity = 2;
    //     string memory id = "order1";
    //     address buyer = address(0x583D6Fe369BCDC9Eb226973Cf59F5e2b5BA9f8D3);
    //     address seller = address(0xfDff78e258aCBDF31544FD4d10Cc8C6e17E5060d);

    //     bytes32 hashed = keccak256(abi.encodePacked(id, buyer, seller, price, quantity));
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashed);
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     console.logBytes(signature);
    // }
}