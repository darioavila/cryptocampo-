// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {BUSD} from "../src/BUSD.sol";
import {CCNFT} from "../src/CCNFT.sol";

contract CCNFTTest is Test {
    address deployer;
    address c1;
    address c2;
    address funds;
    address fees;
    BUSD busd;
    CCNFT ccnft;

    uint256 constant VALUE = 10 ether;

    // Se ejecuta antes de cada test: inicializa direcciones y despliega los contratos.
    function setUp() public {
        deployer = address(this);
        c1 = vm.addr(1);
        c2 = vm.addr(2);
        funds = vm.addr(3);
        fees = vm.addr(4);

        busd = new BUSD();
        ccnft = new CCNFT();

        ccnft.setFundsToken(address(busd));
        ccnft.setFundsCollector(funds);
        ccnft.setFeesCollector(fees);
    }

    // ---------------- SETTERS ----------------

    function testSetFundsCollector() public {
        ccnft.setFundsCollector(c1);
        assertEq(ccnft.fundsCollector(), c1);
    }

    function testSetFeesCollector() public {
        ccnft.setFeesCollector(c1);
        assertEq(ccnft.feesCollector(), c1);
    }

    function testSetProfitToPay() public {
        ccnft.setProfitToPay(1000);
        assertEq(ccnft.profitToPay(), 1000);
    }

    function testSetCanBuy() public {
        ccnft.setCanBuy(true);
        assertTrue(ccnft.canBuy());
        ccnft.setCanBuy(false);
        assertFalse(ccnft.canBuy());
    }

    function testSetCanTrade() public {
        ccnft.setCanTrade(true);
        assertTrue(ccnft.canTrade());
        ccnft.setCanTrade(false);
        assertFalse(ccnft.canTrade());
    }

    function testSetCanClaim() public {
        ccnft.setCanClaim(true);
        assertTrue(ccnft.canClaim());
        ccnft.setCanClaim(false);
        assertFalse(ccnft.canClaim());
    }

    function testSetMaxValueToRaise() public {
        ccnft.setMaxValueToRaise(1000 ether);
        assertEq(ccnft.maxValueToRaise(), 1000 ether);
        ccnft.setMaxValueToRaise(5000 ether);
        assertEq(ccnft.maxValueToRaise(), 5000 ether);
    }

    function testAddValidValues() public {
        ccnft.addValidValues(100);
        assertTrue(ccnft.validValues(100));
        ccnft.addValidValues(200);
        assertTrue(ccnft.validValues(200));
        assertFalse(ccnft.validValues(300));
    }

    function testSetMaxBatchCount() public {
        ccnft.setMaxBatchCount(20);
        assertEq(ccnft.maxBatchCount(), 20);
    }

    function testSetBuyFee() public {
        ccnft.setBuyFee(500);
        assertEq(ccnft.buyFee(), 500);
    }

    function testSetTradeFee() public {
        ccnft.setTradeFee(300);
        assertEq(ccnft.tradeFee(), 300);
    }

    // ---------------- GUARDS DE TRADE ----------------

    function testCannotTradeWhenCanTradeIsFalse() public {
        ccnft.setCanTrade(false);
        vm.expectRevert("Trade is not allowed");
        ccnft.trade(0);
    }

    function testCannotTradeWhenTokenDoesNotExist() public {
        ccnft.setCanTrade(true);
        vm.expectRevert("Token does not exist");
        ccnft.trade(999);
    }

    // ---------------- FLUJO COMPLETO (buy / claim / trade) ----------------

    // Configura el contrato para operar y reparte BUSD a un usuario.
    function _prepare() internal {
        ccnft.setCanBuy(true);
        ccnft.setCanClaim(true);
        ccnft.setCanTrade(true);
        ccnft.setMaxBatchCount(10);
        ccnft.setBuyFee(100); // 1%
        ccnft.setTradeFee(100); // 1%
        ccnft.setProfitToPay(0);
        ccnft.setMaxValueToRaise(100000 ether);
        ccnft.addValidValues(VALUE);

        // El deployer tiene los 10M BUSD del mint. Reparte a c1 y c2.
        busd.transfer(c1, 100000 ether);
        busd.transfer(c2, 100000 ether);
        // fundsCollector necesita BUSD y aprobar para poder pagar los claims.
        busd.transfer(funds, 100000 ether);
        vm.prank(funds);
        busd.approve(address(ccnft), type(uint256).max);
    }

    function testBuyMintsNFTs() public {
        _prepare();

        vm.startPrank(c1);
        busd.approve(address(ccnft), type(uint256).max);
        ccnft.buy(VALUE, 3);
        vm.stopPrank();

        assertEq(ccnft.balanceOf(c1), 3);
        assertEq(ccnft.ownerOf(0), c1);
        assertEq(ccnft.totalValue(), 3 * VALUE);
        // fees = value*amount*buyFee/10000 = 30 * 1% = 0.3
        assertEq(busd.balanceOf(fees), (3 * VALUE * 100) / 10000);
        assertEq(busd.balanceOf(funds), 100000 ether + 3 * VALUE);
    }

    function testBuyRevertsWithInvalidValue() public {
        _prepare();
        vm.startPrank(c1);
        busd.approve(address(ccnft), type(uint256).max);
        vm.expectRevert("Value not allowed");
        ccnft.buy(7 ether, 1);
        vm.stopPrank();
    }

    function testClaimBurnsAndPays() public {
        _prepare();
        ccnft.setProfitToPay(1000); // 10%

        vm.startPrank(c1);
        busd.approve(address(ccnft), type(uint256).max);
        ccnft.buy(VALUE, 2);

        uint256 balBefore = busd.balanceOf(c1);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        ccnft.claim(ids);
        vm.stopPrank();

        assertEq(ccnft.balanceOf(c1), 1); // quemó 1 de 2
        // recibió value + 10% = 10 + 1 = 11
        assertEq(busd.balanceOf(c1), balBefore + VALUE + (VALUE * 1000) / 10000);
    }

    function testPutOnSaleAndTrade() public {
        _prepare();

        // c1 compra 1 NFT (tokenId 0) y lo pone en venta.
        vm.startPrank(c1);
        busd.approve(address(ccnft), type(uint256).max);
        ccnft.buy(VALUE, 1);
        ccnft.putOnSale(0, 12 ether);
        vm.stopPrank();

        // c2 lo compra vía trade.
        vm.startPrank(c2);
        busd.approve(address(ccnft), type(uint256).max);
        ccnft.trade(0);
        vm.stopPrank();

        assertEq(ccnft.ownerOf(0), c2);
        // c1: partió con 100000, pagó 10 (compra) + 0.1 (buyFee 1%), recibió 12 (venta)
        assertEq(busd.balanceOf(c1), 100000 ether - VALUE - (VALUE * 100) / 10000 + 12 ether);
    }

    function testTradeRevertsWhenBuyerIsSeller() public {
        _prepare();
        vm.startPrank(c1);
        busd.approve(address(ccnft), type(uint256).max);
        ccnft.buy(VALUE, 1);
        ccnft.putOnSale(0, 12 ether);
        vm.expectRevert("Buyer is the Seller");
        ccnft.trade(0);
        vm.stopPrank();
    }

    function testDirectTransferIsDisabled() public {
        _prepare();
        vm.startPrank(c1);
        busd.approve(address(ccnft), type(uint256).max);
        ccnft.buy(VALUE, 1);
        vm.expectRevert("Not Allowed");
        ccnft.transferFrom(c1, c2, 0);
        vm.stopPrank();
    }
}
