// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

library EventChainErrors {
    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientPayment();
    error TransferFailed();
    error TicketNotFound();
    error TicketAlreadyUsed();
    error TicketNotForResale();
    error TicketAlreadyListed();
    error ResaleLimitReached();
    error ResalePriceExceedsLimit();
    error ResaleDeadlinePassed();
    error InvalidDate();
    error InvalidEvent();
    error InvalidSignature();
    error EventNotConfigured();
    error EventAlreadyConfigured();
    error EventAlreadyFinalized();
    error MaxTicketsExceeded();
    error PurchaseLimitReached();
    error SignatureExpired();
    error NonceAlreadyUsed();
    error TicketTypeNotConfigured();
    error NoBalanceToWithdraw();
    error NotEventOrganizer();
    error EOCannotBuyTickets();
}
