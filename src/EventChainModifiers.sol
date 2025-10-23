// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {EventChainStorage} from "./EventChainStorage.sol";
import {EventChainErrors} from "./EventChainErrors.sol";

abstract contract EventChainModifiers is EventChainStorage {
    modifier onlyOwner() {
        if (msg.sender != _contractOwner) revert EventChainErrors.Unauthorized();
        _;
    }

    modifier ticketExists(uint256 ticketId) {
        if (_tickets[ticketId].mintedAt == 0) revert EventChainErrors.TicketNotFound();
        _;
    }

    modifier eventConfigured(uint256 eventId) {
        if (_eventCreators[eventId] == address(0)) revert EventChainErrors.EventNotConfigured();
        _;
    }

    modifier eventNotFinalized(uint256 eventId) {
        if (_eventFinalized[eventId]) revert EventChainErrors.EventAlreadyFinalized();
        _;
    }

    modifier withinPurchaseLimit(uint256 eventId, uint256 quantity) {
        if (quantity == 0 || quantity > MAX_TICKETS_PER_PURCHASE) {
            revert EventChainErrors.MaxTicketsExceeded();
        }
        uint256 currentCount = _userEventTicketCount[msg.sender][eventId];
        if (currentCount + quantity > MAX_TICKETS_PER_PURCHASE) {
            revert EventChainErrors.PurchaseLimitReached();
        }
        _;
    }
}