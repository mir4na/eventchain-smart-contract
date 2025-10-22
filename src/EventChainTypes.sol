// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

library EventChainTypes {
    enum EventStatus {
        Pending,
        Approved,
        Rejected
    }

    struct Event {
        uint256 eventId;
        address eventCreator;
        string eventName;
        string eventURI;
        string documentURI;
        uint256 eventDate;
        bool eventActive;
        EventStatus status;
        uint256 createdAt;
        uint256 approvedAt;
    }

    struct TicketType {
        uint256 typeId;
        string typeName;
        uint256 price;
        uint256 totalSupply;
        uint256 sold;
        uint256 saleStartTime;
        uint256 saleEndTime;
        bool active;
    }

    struct Ticket {
        uint256 ticketId;
        uint256 eventId;
        uint256 typeId;
        address currentOwner;
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