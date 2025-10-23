// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {EventChain} from "../src/EventChain.sol";
import {EventChainTypes} from "../src/EventChainTypes.sol";

contract EventChainTest is Test {
    EventChain public eventChain;
    address public owner;
    address public eventCreator;
    address public buyer1;
    address public buyer2;
    address public buyer3;
    address public platform;
    address public backendSigner;
    address public taxWallet;

    uint256 constant EVENT_ID = 123;
    uint256 constant TICKET_TYPE_REGULAR = 1;
    uint256 constant TICKET_PRICE = 0.1 ether;

    function setUp() public {
        owner = makeAddr("owner");
        eventCreator = makeAddr("eventCreator");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");
        buyer3 = makeAddr("buyer3");
        platform = makeAddr("platform");
        backendSigner = makeAddr("backendSigner");
        taxWallet = makeAddr("taxWallet");

        vm.deal(owner, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
        vm.deal(buyer3, 100 ether);

        vm.prank(owner);
        eventChain = new EventChain(platform, backendSigner);
    }

    function test_Deployment() public {
        assertEq(eventChain.platformWallet(), platform);
        assertEq(eventChain.backendSigner(), backendSigner);
    }

    function test_ConfigureEvent() public {
        vm.prank(owner);
        bool success = eventChain.configureEvent(EVENT_ID, eventCreator, taxWallet);
        assertTrue(success);
    }

    function test_BuyTickets() public {
        vm.prank(owner);
        eventChain.configureEvent(EVENT_ID, eventCreator, taxWallet);
        
        vm.prank(owner);
        eventChain.setTicketTypePrice(EVENT_ID, TICKET_TYPE_REGULAR, TICKET_PRICE);

        uint256 quantity = 2;
        uint256 totalCost = TICKET_PRICE * quantity;

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = eventCreator;
        beneficiaries[1] = platform;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 8000; // 80%
        percentages[1] = 2000; // 20%

        vm.prank(buyer1);
        uint256[] memory ticketIds = eventChain.buyTickets{value: totalCost}(
            EVENT_ID,
            TICKET_TYPE_REGULAR,
            quantity,
            beneficiaries,
            percentages
        );

        assertEq(ticketIds.length, quantity);
        assertEq(eventChain.ownerOf(ticketIds[0]), buyer1);

        EventChainTypes.Ticket memory ticket = eventChain.getTicketDetails(ticketIds[0]);
        assertEq(ticket.eventId, EVENT_ID);
        assertEq(ticket.originalPrice, TICKET_PRICE);
        assertEq(ticket.resaleCount, 0);
    }

    function test_BuyMaxTickets() public {
        vm.prank(owner);
        eventChain.configureEvent(EVENT_ID, eventCreator, taxWallet);
        
        vm.prank(owner);
        eventChain.setTicketTypePrice(EVENT_ID, TICKET_TYPE_REGULAR, TICKET_PRICE);

        uint256 quantity = 5;
        uint256 totalCost = TICKET_PRICE * quantity;

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = eventCreator;
        beneficiaries[1] = platform;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 8000;
        percentages[1] = 2000;

        vm.prank(buyer1);
        uint256[] memory ticketIds = eventChain.buyTickets{value: totalCost}(
            EVENT_ID,
            TICKET_TYPE_REGULAR,
            quantity,
            beneficiaries,
            percentages
        );

        assertEq(ticketIds.length, quantity);
    }

    function test_BuyExceedingMaxTickets() public {
        vm.prank(owner);
        eventChain.configureEvent(EVENT_ID, eventCreator, taxWallet);
        
        vm.prank(owner);
        eventChain.setTicketTypePrice(EVENT_ID, TICKET_TYPE_REGULAR, TICKET_PRICE);

        uint256 quantity = 6;
        uint256 totalCost = TICKET_PRICE * quantity;

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = eventCreator;
        beneficiaries[1] = platform;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 8000;
        percentages[1] = 2000;

        vm.prank(buyer1);
        vm.expectRevert("MaxTicketsExceeded()");
        eventChain.buyTickets{value: totalCost}(
            EVENT_ID,
            TICKET_TYPE_REGULAR,
            quantity,
            beneficiaries,
            percentages
        );
    }

    function test_ListAndBuyResaleTicket() public {
        vm.prank(owner);
        eventChain.configureEvent(EVENT_ID, eventCreator, taxWallet);
        
        vm.prank(owner);
        eventChain.setTicketTypePrice(EVENT_ID, TICKET_TYPE_REGULAR, TICKET_PRICE);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = eventCreator;
        beneficiaries[1] = platform;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 8000;
        percentages[1] = 2000;

        vm.prank(buyer1);
        uint256[] memory ids = eventChain.buyTickets{value: TICKET_PRICE}(
            EVENT_ID,
            TICKET_TYPE_REGULAR,
            1,
            beneficiaries,
            percentages
        );
        uint256 ticketId = ids[0];

        uint256 resalePrice = (TICKET_PRICE * 110) / 100;
        uint256 deadline = block.timestamp + 7 days;

        vm.prank(buyer1);
        eventChain.listTicketForResale(ticketId, resalePrice, deadline);

        vm.prank(buyer2);
        eventChain.buyResaleTicket{value: resalePrice}(ticketId);

        assertEq(eventChain.ownerOf(ticketId), buyer2);
    }
}