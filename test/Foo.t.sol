// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { LibraContract } from "../src/LibraContract.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LibraContractTest is Test {
    using ECDSA for bytes32;
    enum OrderStatus {Paid, Shipped, Completed, Cancelled}
    struct Order {
        string id;
        address buyer;
        address seller;
        uint256 price;
        uint256 quantity;
        uint256 payTime;
        OrderStatus state;
    }
    LibraContract _libra;

    function setUp() public {
        _libra = new LibraContract();
    }

    function testCreateOrder() public {
        _libra.setSigner(0x19A6acE647842f55F6DF65973f72bfB298398c2c);
        // 模拟下单数据
        string memory id = "order1";
        address buyer = address(0xf3efBad1f23b25B0941Ba114f0f185718BaE0375); 
        address seller = address(0x19A6acE647842f55F6DF65973f72bfB298398c2c);
        uint price = 1 ether;
        uint quantity = 2;

        // 模拟签名
        uint256 privateKey = 0x4208f1cfd43f87cad512ee1163b8f96f13e631174619f6ad81b7acc4298444b2;

        bytes32 hashed = keccak256(abi.encodePacked(id, buyer, seller, price, quantity));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashed);
        bytes memory signature = abi.encodePacked(r, s, v);
        console.logBytes(signature);
        // 下单
        // vm.startPrank(buyer);
        _libra.createOrder{value: price * quantity}(
            id, buyer, seller, price, quantity, signature
        );

        address order = _libra.getOrderBuyer(id);
        assertEq(order, buyer);
    }

    // function testSetSigner() public {
    // }

    // function testCancelOrder() public {
    // }
}