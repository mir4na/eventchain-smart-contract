// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {EventChain} from "../src/EventChain.sol";

contract EventChainTest is Test {
    EventChain public eventChain;
    address organizer = address(0x123);
    address artist = address(0x456);
    address platform = address(0x789);
    address buyer = address(0xABC);

    function setUp() public {
        eventChain = new EventChain();
    }

    function testCreateEvent() public {
        // Declare arrays dengan ukuran yang tepat
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = organizer;
        beneficiaries[1] = artist;
        beneficiaries[2] = platform;

        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000; // 50%
        percentages[1] = 3000; // 30%
        percentages[2] = 2000; // 20%

        vm.prank(organizer);
        uint256 eventId = eventChain.createEvent(
            "Test Concert",
            "ipfs://QmTest",
            0.1 ether,
            100,
            block.timestamp + 30 days,
            beneficiaries,
            percentages
        );

        assertEq(eventId, 1);
        
        EventChain.Event memory evt = eventChain.getEventDetails(eventId);
        assertEq(evt.eventName, "Test Concert");
        assertEq(evt.ticketPrice, 0.1 ether);
        assertEq(evt.totalTickets, 100);
        assertTrue(evt.eventActive);
    }

    function testBuyTicket() public {
        // Setup event first
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = organizer;
        beneficiaries[1] = artist;
        beneficiaries[2] = platform;

        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000;
        percentages[1] = 3000;
        percentages[2] = 2000;

        vm.prank(organizer);
        uint256 eventId = eventChain.createEvent(
            "Test Concert",
            "ipfs://QmTest",
            0.1 ether,
            100,
            block.timestamp + 30 days,
            beneficiaries,
            percentages
        );

        // Buy ticket
        vm.prank(buyer);
        vm.deal(buyer, 1 ether);
        eventChain.buyTicket{value: 0.1 ether}(eventId);

        // Verify ticket minted
        assertEq(eventChain.balanceOf(buyer), 1);
        
        EventChain.Ticket memory ticket = eventChain.getTicketDetails(1);
        assertEq(ticket.currentOwner, buyer);
        assertFalse(ticket.isUsed);
    }

    function testRevenueDistribution() public {
        // Setup event
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = organizer;
        beneficiaries[1] = artist;
        beneficiaries[2] = platform;

        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000; // 50%
        percentages[1] = 3000; // 30%
        percentages[2] = 2000; // 20%

        vm.prank(organizer);
        uint256 eventId = eventChain.createEvent(
            "Test Concert",
            "ipfs://QmTest",
            1 ether,
            100,
            block.timestamp + 30 days,
            beneficiaries,
            percentages
        );

        // Record balances before
        uint256 organizerBefore = organizer.balance;
        uint256 artistBefore = artist.balance;
        uint256 platformBefore = platform.balance;

        // Buy ticket
        vm.prank(buyer);
        vm.deal(buyer, 2 ether);
        eventChain.buyTicket{value: 1 ether}(eventId);

        // Verify distributions
        assertEq(organizer.balance, organizerBefore + 0.5 ether);
        assertEq(artist.balance, artistBefore + 0.3 ether);
        assertEq(platform.balance, platformBefore + 0.2 ether);
    }

    function testResaleTicket() public {
        // Setup event
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = organizer;
        beneficiaries[1] = artist;
        beneficiaries[2] = platform;

        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000;
        percentages[1] = 3000;
        percentages[2] = 2000;

        vm.prank(organizer);
        uint256 eventId = eventChain.createEvent(
            "Test Concert",
            "ipfs://QmTest",
            0.1 ether,
            100,
            block.timestamp + 30 days,
            beneficiaries,
            percentages
        );

        // Original purchase
        vm.prank(buyer);
        vm.deal(buyer, 1 ether);
        eventChain.buyTicket{value: 0.1 ether}(eventId);

        // List for resale
        vm.prank(buyer);
        eventChain.listTicketForResale(1, 0.15 ether);

        // Someone else buys resale
        address buyer2 = address(0xDEF);
        vm.prank(buyer2);
        vm.deal(buyer2, 1 ether);
        eventChain.buyResaleTicket{value: 0.15 ether}(1);

        // Verify ownership transferred
        assertEq(eventChain.ownerOf(1), buyer2);
        assertFalse(eventChain.ticketForSale(1));
    }
}