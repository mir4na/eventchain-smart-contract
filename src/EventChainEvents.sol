// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

abstract contract EventChainEvents {
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event PlatformWalletUpdated(address indexed newWallet);

    event EventCreated(uint256 indexed eventId, address indexed creator, string eventName);
    event EventApproved(uint256 indexed eventId, address indexed creator);
    event EventRejected(uint256 indexed eventId, address indexed creator);
    event EventDeactivated(uint256 indexed eventId);

    event TicketTypeAdded(uint256 indexed eventId, uint256 indexed typeId, string typeName, uint256 price, uint256 supply);
    event TicketTypeUpdated(uint256 indexed eventId, uint256 indexed typeId, uint256 price, uint256 supply);

    event TicketMinted(uint256 indexed ticketId, uint256 indexed eventId, uint256 indexed typeId, address buyer);
    event TicketsPurchased(uint256 indexed eventId, uint256 indexed typeId, address indexed buyer, uint256 quantity, uint256 totalCost);
    event TicketUsed(uint256 indexed ticketId, uint256 indexed eventId, address indexed user);

    event TicketListedForResale(uint256 indexed ticketId, uint256 resalePrice, uint256 deadline);
    event TicketResold(uint256 indexed ticketId, address indexed from, address indexed to, uint256 price);
    event ResaleListingCancelled(uint256 indexed ticketId);
}