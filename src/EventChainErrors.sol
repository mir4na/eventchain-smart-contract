// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

library EventChainErrors {
    error Unauthorized();
    error OnlyAdmin();
    error OnlyEventCreator();
    error EventNotFound();
    error TicketNotFound();
    error TicketTypeNotFound();
    error TicketTypeInactive();
    error InvalidAddress();
    error InvalidPrice();
    error InvalidAmount();
    error InvalidDate();
    error InvalidPercentage();
    error EventInactive();
    error TicketsSoldOut();
    error InsufficientPayment();
    error ExcessPayment();
    error TicketAlreadyUsed();
    error TicketNotForResale();
    error ResaleDeadlinePassed();
    error ResaleLimitReached();
    error ResalePriceExceedsLimit();
    error TransferFailed();
    error TicketAlreadyListed();
    error EventNotApproved();
    error EventAlreadyProcessed();
    error EventAlreadyConfigured();
    error SaleNotStarted();
    error SaleEnded();
    error PurchaseLimitExceeded();
}