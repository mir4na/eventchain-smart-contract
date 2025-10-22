// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {EventChainStorage} from "./EventChainStorage.sol";
import {EventChainErrors} from "./EventChainErrors.sol";

abstract contract EventChainModifiers is EventChainStorage {
    modifier onlyOwner() {
        if (msg.sender != _contractOwner) {
            revert EventChainErrors.Unauthorized();
        }
        _;
    }

    modifier onlyAdmin() {
        if (!admins[msg.sender] && msg.sender != _contractOwner) {
            revert EventChainErrors.OnlyAdmin();
        }
        _;
    }

    modifier eventExists(uint256 eventId) {
        if (_events[eventId].eventId == 0) {
            revert EventChainErrors.EventNotFound();
        }
        _;
    }

    modifier ticketExists(uint256 ticketId) {
        if (_tickets[ticketId].ticketId == 0) {
            revert EventChainErrors.TicketNotFound();
        }
        _;
    }

    modifier onlyEventCreator(uint256 eventId) {
        if (msg.sender != _events[eventId].eventCreator) {
            revert EventChainErrors.OnlyEventCreator();
        }
        _;
    }

    function owner() public view returns (address) {
        return _contractOwner;
    }
}