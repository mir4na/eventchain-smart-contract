// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

abstract contract EventChainEvents {
    event PlatformWalletUpdated(address indexed newWallet);
    event BackendSignerUpdated(address indexed newSigner);
    event EventFinalized(uint256 indexed eventId);
    event TokenURIUpdated(uint256 indexed ticketId, string uri);
    event TicketTypePriceSet(uint256 indexed eventId, uint256 indexed typeId, uint256 price);
    event Withdrawn(address indexed user, uint256 amount);

    event RevenueConfigured(
        uint256 indexed eventId,
        address indexed creator,
        address indexed taxWallet
    );

    event TicketMinted(
        uint256 indexed ticketId,
        uint256 indexed eventId,
        uint256 indexed typeId,
        address buyer,
        uint256 price
    );

    event TicketsPurchased(
        uint256 indexed eventId,
        uint256 indexed typeId,
        address indexed buyer,
        uint256 quantity,
        uint256 totalCost,
        uint256 taxAmount,
        uint256[] ticketIds
    );

    event TicketListedForResale(
        uint256 indexed ticketId,
        uint256 indexed eventId,
        address indexed seller,
        uint256 resalePrice,
        uint256 deadline
    );

    event TicketResold(
        uint256 indexed ticketId,
        uint256 indexed eventId,
        address indexed from,
        address to,
        uint256 price,
        uint256 taxAmount
    );

    event ResaleListingCancelled(
        uint256 indexed ticketId,
        address indexed seller
    );

    event TicketUsed(
        uint256 indexed ticketId,
        uint256 indexed eventId,
        address indexed user,
        uint256 timestamp
    );

    event RevenueDistributed(
        uint256 indexed eventId,
        uint256 totalAmount,
        uint256 taxAmount,
        uint256 netAmount,
        uint256 timestamp
    );
}