// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {EventChainTypes} from "./EventChainTypes.sol";

abstract contract EventChainStorage {
    address internal _contractOwner;
    address public platformWallet;
    address public backendSigner;

    uint256 public constant TAX_PERCENTAGE = 1000;
    uint256 public constant PLATFORM_FEE = 250;
    uint256 public constant CREATOR_ROYALTY = 500;
    uint256 public constant MAX_RESALE_PERCENTAGE = 120;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_TICKETS_PER_PURCHASE = 5;

    uint256 internal _currentTicketId;

    mapping(uint256 => EventChainTypes.Ticket) internal _tickets;
    mapping(uint256 => address) internal _eventCreators;
    mapping(uint256 => address) internal _taxWallets;
    mapping(uint256 => bool) internal _eventFinalized;
    mapping(uint256 => mapping(uint256 => uint256)) internal _ticketTypePrices;
    mapping(address => uint256[]) internal _userTickets;
    mapping(address => mapping(uint256 => uint256)) internal _userEventTicketCount;
    mapping(uint256 => mapping(uint256 => bool)) internal _usedNonces;
    mapping(uint256 => string) internal _tokenURIs;
    mapping(address => uint256) internal _pendingWithdrawals;
    mapping(address => bool) internal _eoAddresses;

    uint256[] internal _resaleTicketIds;
    mapping(uint256 => uint256) internal _resaleTicketIndex;
}