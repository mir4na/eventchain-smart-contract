// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {EventChainTypes} from "./EventChainTypes.sol";

abstract contract EventChainStorage {
    address public platformWallet;
    address internal _contractOwner;

    uint256 public constant PLATFORM_FEE = 250;
    uint256 public constant CREATOR_ROYALTY = 500;
    uint256 public constant MAX_RESALE_PERCENTAGE = 120;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_RESALE_COUNT = 1;
    uint256 public constant MAX_TICKETS_PER_USER = 5;
    uint256 public constant MAX_TICKETS_PER_PURCHASE = 5;

    uint256 internal _currentEventId;
    uint256 internal _currentTicketId;
    uint256 internal _currentTicketTypeId;

    mapping(address => bool) public admins;

    mapping(uint256 => EventChainTypes.Event) internal _events;
    mapping(uint256 => EventChainTypes.Ticket) internal _tickets;
    mapping(uint256 => EventChainTypes.RevenueShare[]) internal _revenueShares;

    mapping(uint256 => mapping(uint256 => EventChainTypes.TicketType)) internal _ticketTypes;
    mapping(uint256 => uint256[]) internal _eventTicketTypes;

    mapping(address => uint256[]) internal _userTickets;
    mapping(address => uint256[]) internal _eoEvents;
    mapping(address => mapping(uint256 => uint256)) internal _userEventPurchases;

    uint256[] internal _resaleTicketIds;
    mapping(uint256 => uint256) internal _resaleTicketIndex;
}