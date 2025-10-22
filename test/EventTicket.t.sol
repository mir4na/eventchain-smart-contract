// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {EventChain} from "../src/EventChain.sol";
import {EventChainTypes} from "../src/EventChainTypes.sol";
import {EventChainErrors} from "../src/EventChainErrors.sol";

contract EventChainTest is Test {
    EventChain public eventChain;

    address public owner;
    address public admin;
    address public eo;
    address public buyer1;
    address public buyer2;
    address public buyer3;
    address public platform;
    address public beneficiary1;
    address public beneficiary2;

    uint256 constant TICKET_PRICE = 0.1 ether;
    uint256 constant VIP_PRICE = 0.5 ether;
    uint256 constant TOTAL_SUPPLY = 100;

    function setUp() public {
        owner = makeAddr("owner");
        admin = makeAddr("admin");
        eo = makeAddr("eo");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");
        buyer3 = makeAddr("buyer3");
        platform = makeAddr("platform");
        beneficiary1 = makeAddr("beneficiary1");
        beneficiary2 = makeAddr("beneficiary2");

        vm.deal(owner, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
        vm.deal(buyer3, 100 ether);

        vm.prank(owner);
        eventChain = new EventChain();

        vm.prank(owner);
        eventChain.setPlatformWallet(platform);

        vm.prank(owner);
        eventChain.addAdmin(admin);
    }

    function test_Deployment() public view {
        assertEq(eventChain.owner(), owner);
        assertEq(eventChain.platformWallet(), platform);
        assertTrue(eventChain.isAdmin(admin));
        assertTrue(eventChain.isAdmin(owner));
    }

    function test_CreateEvent() public {
        vm.startPrank(eo);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 7000;
        percentages[1] = 3000;

        uint256 eventId = eventChain.createEvent(
            "Concert 2025",
            "ipfs://event-metadata",
            "ipfs://event-documents",
            block.timestamp + 30 days,
            beneficiaries,
            percentages
        );

        vm.stopPrank();

        assertEq(eventId, 1);

        EventChainTypes.Event memory eventData = eventChain.getEventDetails(eventId);
        assertEq(eventData.eventName, "Concert 2025");
        assertEq(eventData.eventCreator, eo);
        assertEq(uint256(eventData.status), uint256(EventChainTypes.EventStatus.Pending));
    }

    function test_ApproveEvent() public {
        uint256 eventId = _createTestEvent();

        vm.prank(admin);
        eventChain.approveEvent(eventId);

        EventChainTypes.Event memory eventData = eventChain.getEventDetails(eventId);
        assertEq(uint256(eventData.status), uint256(EventChainTypes.EventStatus.Approved));
    }

    function test_AddMultipleTicketTypes() public {
        uint256 eventId = _createAndApproveEvent();

        vm.startPrank(eo);

        uint256 regularTypeId = eventChain.addTicketType(
            eventId,
            "Regular",
            TICKET_PRICE,
            TOTAL_SUPPLY,
            block.timestamp + 1 days,
            block.timestamp + 10 days
        );

        uint256 vipTypeId = eventChain.addTicketType(
            eventId,
            "VIP",
            VIP_PRICE,
            50,
            block.timestamp + 1 days,
            block.timestamp + 10 days
        );

        vm.stopPrank();

        assertEq(regularTypeId, 1);
        assertEq(vipTypeId, 2);

        EventChainTypes.TicketType memory regularType = eventChain.getTicketType(eventId, regularTypeId);
        assertEq(regularType.typeName, "Regular");
        assertEq(regularType.price, TICKET_PRICE);

        EventChainTypes.TicketType memory vipType = eventChain.getTicketType(eventId, vipTypeId);
        assertEq(vipType.typeName, "VIP");
        assertEq(vipType.price, VIP_PRICE);
    }

    function test_BuySingleTicket() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);

        uint256[] memory userTickets = eventChain.getUserTickets(buyer1);
        assertEq(userTickets.length, 1);

        EventChainTypes.Ticket memory ticket = eventChain.getTicketDetails(userTickets[0]);
        assertEq(ticket.eventId, eventId);
        assertEq(ticket.typeId, typeId);
        assertEq(ticket.currentOwner, buyer1);
    }

    function test_BuyMultipleTickets() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 quantity = 3;
        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE * quantity}(eventId, typeId, quantity);

        uint256[] memory userTickets = eventChain.getUserTickets(buyer1);
        assertEq(userTickets.length, quantity);

        uint256 purchaseCount = eventChain.getUserPurchaseCount(buyer1, eventId);
        assertEq(purchaseCount, quantity);
    }

    function test_CannotBuyMoreThanMaxPerUser() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE * 5}(eventId, typeId, 5);

        vm.expectRevert(EventChainErrors.PurchaseLimitExceeded.selector);
        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);
    }

    function test_CannotBuyMoreThanMaxPerPurchase() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(EventChainErrors.InvalidAmount.selector);
        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE * 6}(eventId, typeId, 6);
    }

    function test_RevenueDistribution() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 balanceBefore1 = beneficiary1.balance;
        uint256 balanceBefore2 = beneficiary2.balance;

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);

        uint256 balanceAfter1 = beneficiary1.balance;
        uint256 balanceAfter2 = beneficiary2.balance;

        assertEq(balanceAfter1 - balanceBefore1, TICKET_PRICE * 70 / 100);
        assertEq(balanceAfter2 - balanceBefore2, TICKET_PRICE * 30 / 100);
    }

    function test_ListTicketForResale() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);

        uint256[] memory userTickets = eventChain.getUserTickets(buyer1);
        uint256 ticketId = userTickets[0];

        uint256 resalePrice = TICKET_PRICE * 110 / 100;
        uint256 deadline = block.timestamp + 5 days;

        vm.prank(buyer1);
        eventChain.listTicketForResale(ticketId, resalePrice, deadline);

        EventChainTypes.Ticket memory ticket = eventChain.getTicketDetails(ticketId);
        assertTrue(ticket.isForResale);
        assertEq(ticket.resalePrice, resalePrice);
    }

    function test_BuyResaleTicket() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);

        uint256[] memory userTickets = eventChain.getUserTickets(buyer1);
        uint256 ticketId = userTickets[0];

        uint256 resalePrice = TICKET_PRICE * 110 / 100;
        uint256 deadline = block.timestamp + 5 days;

        vm.prank(buyer1);
        eventChain.listTicketForResale(ticketId, resalePrice, deadline);

        uint256 eoBalanceBefore = eo.balance;
        uint256 platformBalanceBefore = platform.balance;
        uint256 sellerBalanceBefore = buyer1.balance;

        vm.prank(buyer2);
        eventChain.buyResaleTicket{value: resalePrice}(ticketId);

        uint256 creatorFee = resalePrice * 500 / 10000;
        uint256 platformFee = resalePrice * 250 / 10000;
        uint256 sellerProceeds = resalePrice - creatorFee - platformFee;

        assertEq(eo.balance - eoBalanceBefore, creatorFee);
        assertEq(platform.balance - platformBalanceBefore, platformFee);
        assertEq(buyer1.balance - sellerBalanceBefore, sellerProceeds);

        assertEq(eventChain.ownerOf(ticketId), buyer2);
    }

    function test_CannotResellMoreThanOnce() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);

        uint256[] memory userTickets = eventChain.getUserTickets(buyer1);
        uint256 ticketId = userTickets[0];

        uint256 resalePrice = TICKET_PRICE * 110 / 100;
        uint256 deadline = block.timestamp + 5 days;

        vm.prank(buyer1);
        eventChain.listTicketForResale(ticketId, resalePrice, deadline);

        vm.prank(buyer2);
        eventChain.buyResaleTicket{value: resalePrice}(ticketId);

        vm.expectRevert(EventChainErrors.ResaleLimitReached.selector);
        vm.prank(buyer2);
        eventChain.listTicketForResale(ticketId, resalePrice, deadline);
    }

    function test_CannotResellAboveMaxPrice() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);

        uint256[] memory userTickets = eventChain.getUserTickets(buyer1);
        uint256 ticketId = userTickets[0];

        uint256 tooHighPrice = TICKET_PRICE * 121 / 100;
        uint256 deadline = block.timestamp + 5 days;

        vm.expectRevert(EventChainErrors.ResalePriceExceedsLimit.selector);
        vm.prank(buyer1);
        eventChain.listTicketForResale(ticketId, tooHighPrice, deadline);
    }

    function test_UseTicket() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);

        uint256[] memory userTickets = eventChain.getUserTickets(buyer1);
        uint256 ticketId = userTickets[0];

        vm.prank(eo);
        eventChain.useTicket(ticketId, eventId);

        EventChainTypes.Ticket memory ticket = eventChain.getTicketDetails(ticketId);
        assertTrue(ticket.isUsed);
        assertGt(ticket.usedAt, 0);
    }

    function test_CannotUseTicketTwice() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);

        uint256[] memory userTickets = eventChain.getUserTickets(buyer1);
        uint256 ticketId = userTickets[0];

        vm.prank(eo);
        eventChain.useTicket(ticketId, eventId);

        vm.expectRevert(EventChainErrors.TicketAlreadyUsed.selector);
        vm.prank(eo);
        eventChain.useTicket(ticketId, eventId);
    }

    function test_UpdateTicketType() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        uint256 newPrice = 0.15 ether;
        uint256 newSupply = 150;

        vm.prank(eo);
        eventChain.updateTicketType(
            eventId,
            typeId,
            newPrice,
            newSupply,
            block.timestamp + 1 days,
            block.timestamp + 10 days,
            true
        );

        EventChainTypes.TicketType memory ticketType = eventChain.getTicketType(eventId, typeId);
        assertEq(ticketType.price, newPrice);
        assertEq(ticketType.totalSupply, newSupply);
    }

    function test_CancelResaleListing() public {
        uint256 eventId = _createAndApproveEvent();
        uint256 typeId = _addTicketType(eventId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(buyer1);
        eventChain.buyTickets{value: TICKET_PRICE}(eventId, typeId, 1);

        uint256[] memory userTickets = eventChain.getUserTickets(buyer1);
        uint256 ticketId = userTickets[0];

        uint256 resalePrice = TICKET_PRICE * 110 / 100;
        uint256 deadline = block.timestamp + 5 days;

        vm.prank(buyer1);
        eventChain.listTicketForResale(ticketId, resalePrice, deadline);

        vm.prank(buyer1);
        eventChain.cancelResaleListing(ticketId);

        EventChainTypes.Ticket memory ticket = eventChain.getTicketDetails(ticketId);
        assertFalse(ticket.isForResale);
        assertEq(ticket.resalePrice, 0);
    }

    function _createTestEvent() internal returns (uint256) {
        vm.startPrank(eo);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 7000;
        percentages[1] = 3000;

        uint256 eventId = eventChain.createEvent(
            "Test Event",
            "ipfs://metadata",
            "ipfs://docs",
            block.timestamp + 30 days,
            beneficiaries,
            percentages
        );

        vm.stopPrank();
        return eventId;
    }

    function _createAndApproveEvent() internal returns (uint256) {
        uint256 eventId = _createTestEvent();
        vm.prank(admin);
        eventChain.approveEvent(eventId);
        return eventId;
    }

    function _addTicketType(uint256 eventId) internal returns (uint256) {
        vm.prank(eo);
        return eventChain.addTicketType(
            eventId,
            "Regular",
            TICKET_PRICE,
            TOTAL_SUPPLY,
            block.timestamp + 1 days,
            block.timestamp + 10 days
        );
    }
}