// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

library EventChainTypes {
    struct Ticket {
        uint256 ticketId;
        uint256 eventId;
        uint256 typeId;
        address currentOwner;
        uint256 originalPrice;
        bool isUsed;
        uint256 mintedAt;
        uint256 usedAt;
        bool isForResale;
        uint256 resalePrice;
        uint256 resaleDeadline;
        uint8 resaleCount;
    }

    struct RevenueShare {
        address beneficiary;
        uint256 percentage;
    }
}