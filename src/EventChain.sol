// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EventChainStorage} from "./EventChainStorage.sol";
import {EventChainModifiers} from "./EventChainModifiers.sol";
import {EventChainEvents} from "./EventChainEvents.sol";
import {EventChainTypes} from "./EventChainTypes.sol";
import {EventChainErrors} from "./EventChainErrors.sol";

contract EventChain is ERC721, ReentrancyGuard, EventChainModifiers, EventChainEvents {
    constructor() ERC721("EventChain Ticket", "EVTKT") {
        _contractOwner = msg.sender;
    }

    function addAdmin(address admin) external onlyOwner {
        if (admin == address(0)) revert EventChainErrors.InvalidAddress();
        admins[admin] = true;
        emit AdminAdded(admin);
    }

    function removeAdmin(address admin) external onlyOwner {
        admins[admin] = false;
        emit AdminRemoved(admin);
    }

    function setPlatformWallet(address wallet) external onlyOwner {
        if (wallet == address(0)) revert EventChainErrors.InvalidAddress();
        platformWallet = wallet;
        emit PlatformWalletUpdated(wallet);
    }

    function createEvent(
        string calldata eventName,
        string calldata eventURI,
        string calldata documentURI,
        uint256 eventDate,
        address[] calldata revenueBeneficiaries,
        uint256[] calldata percentages
    ) external returns (uint256) {
        if (eventDate <= block.timestamp) revert EventChainErrors.InvalidDate();
        if (revenueBeneficiaries.length != percentages.length) {
            revert EventChainErrors.InvalidPercentage();
        }
        if (revenueBeneficiaries.length == 0) {
            revert EventChainErrors.InvalidAmount();
        }

        _validatePercentages(percentages);

        unchecked {
            ++_currentEventId;
        }
        uint256 eventId = _currentEventId;

        _events[eventId] = EventChainTypes.Event({
            eventId: eventId,
            eventCreator: msg.sender,
            eventName: eventName,
            eventURI: eventURI,
            documentURI: documentURI,
            eventDate: eventDate,
            eventActive: false,
            status: EventChainTypes.EventStatus.Pending,
            createdAt: block.timestamp,
            approvedAt: 0
        });

        _setupRevenueShares(eventId, revenueBeneficiaries, percentages);
        _eoEvents[msg.sender].push(eventId);

        emit EventCreated(eventId, msg.sender, eventName);
        return eventId;
    }

    function approveEvent(uint256 eventId) external onlyAdmin eventExists(eventId) {
        EventChainTypes.Event storage eventData = _events[eventId];

        if (eventData.status != EventChainTypes.EventStatus.Pending) {
            revert EventChainErrors.EventAlreadyProcessed();
        }

        eventData.status = EventChainTypes.EventStatus.Approved;
        eventData.approvedAt = block.timestamp;

        emit EventApproved(eventId, eventData.eventCreator);
    }

    function rejectEvent(uint256 eventId) external onlyAdmin eventExists(eventId) {
        EventChainTypes.Event storage eventData = _events[eventId];

        if (eventData.status != EventChainTypes.EventStatus.Pending) {
            revert EventChainErrors.EventAlreadyProcessed();
        }

        eventData.status = EventChainTypes.EventStatus.Rejected;

        emit EventRejected(eventId, eventData.eventCreator);
    }

    function addTicketType(
        uint256 eventId,
        string calldata typeName,
        uint256 price,
        uint256 supply,
        uint256 saleStart,
        uint256 saleEnd
    ) external eventExists(eventId) onlyEventCreator(eventId) returns (uint256) {
        EventChainTypes.Event storage eventData = _events[eventId];

        if (eventData.status != EventChainTypes.EventStatus.Approved) {
            revert EventChainErrors.EventNotApproved();
        }
        if (price == 0) revert EventChainErrors.InvalidPrice();
        if (supply == 0) revert EventChainErrors.InvalidAmount();
        if (saleStart < block.timestamp) revert EventChainErrors.InvalidDate();
        if (saleEnd <= saleStart) revert EventChainErrors.InvalidDate();
        if (saleEnd > eventData.eventDate) revert EventChainErrors.InvalidDate();

        unchecked {
            ++_currentTicketTypeId;
        }
        uint256 typeId = _currentTicketTypeId;

        _ticketTypes[eventId][typeId] = EventChainTypes.TicketType({
            typeId: typeId,
            typeName: typeName,
            price: price,
            totalSupply: supply,
            sold: 0,
            saleStartTime: saleStart,
            saleEndTime: saleEnd,
            active: true
        });

        _eventTicketTypes[eventId].push(typeId);

        if (!eventData.eventActive) {
            eventData.eventActive = true;
        }

        emit TicketTypeAdded(eventId, typeId, typeName, price, supply);
        return typeId;
    }

    function updateTicketType(
        uint256 eventId,
        uint256 typeId,
        uint256 price,
        uint256 supply,
        uint256 saleStart,
        uint256 saleEnd,
        bool active
    ) external eventExists(eventId) onlyEventCreator(eventId) {
        EventChainTypes.TicketType storage ticketType = _ticketTypes[eventId][typeId];
        
        if (ticketType.typeId == 0) revert EventChainErrors.TicketTypeNotFound();
        if (price == 0) revert EventChainErrors.InvalidPrice();
        if (supply < ticketType.sold) revert EventChainErrors.InvalidAmount();
        if (saleStart < block.timestamp) revert EventChainErrors.InvalidDate();
        if (saleEnd <= saleStart) revert EventChainErrors.InvalidDate();
        if (saleEnd > _events[eventId].eventDate) revert EventChainErrors.InvalidDate();

        ticketType.price = price;
        ticketType.totalSupply = supply;
        ticketType.saleStartTime = saleStart;
        ticketType.saleEndTime = saleEnd;
        ticketType.active = active;

        emit TicketTypeUpdated(eventId, typeId, price, supply);
    }

    function buyTickets(
        uint256 eventId,
        uint256 typeId,
        uint256 quantity
    ) external payable eventExists(eventId) nonReentrant {
        if (quantity == 0 || quantity > MAX_TICKETS_PER_PURCHASE) {
            revert EventChainErrors.InvalidAmount();
        }

        EventChainTypes.Event storage eventData = _events[eventId];
        EventChainTypes.TicketType storage ticketType = _ticketTypes[eventId][typeId];

        if (eventData.status != EventChainTypes.EventStatus.Approved) {
            revert EventChainErrors.EventNotApproved();
        }
        if (!eventData.eventActive) revert EventChainErrors.EventInactive();
        if (ticketType.typeId == 0) revert EventChainErrors.TicketTypeNotFound();
        if (!ticketType.active) revert EventChainErrors.TicketTypeInactive();
        if (block.timestamp < ticketType.saleStartTime) revert EventChainErrors.SaleNotStarted();
        if (block.timestamp > ticketType.saleEndTime) revert EventChainErrors.SaleEnded();

        uint256 userPurchased = _userEventPurchases[msg.sender][eventId];
        if (userPurchased + quantity > MAX_TICKETS_PER_USER) {
            revert EventChainErrors.PurchaseLimitExceeded();
        }

        if (ticketType.sold + quantity > ticketType.totalSupply) {
            revert EventChainErrors.TicketsSoldOut();
        }

        uint256 totalCost = ticketType.price * quantity;
        if (msg.value != totalCost) revert EventChainErrors.InsufficientPayment();

        for (uint256 i; i < quantity;) {
            unchecked {
                ++_currentTicketId;
            }
            uint256 ticketId = _currentTicketId;

            _createTicket(ticketId, eventId, typeId);
            _safeMint(msg.sender, ticketId);
            _userTickets[msg.sender].push(ticketId);

            emit TicketMinted(ticketId, eventId, typeId, msg.sender);

            unchecked { ++i; }
        }

        unchecked {
            ticketType.sold += quantity;
            _userEventPurchases[msg.sender][eventId] += quantity;
        }

        _distributeRevenue(eventId, msg.value);

        emit TicketsPurchased(eventId, typeId, msg.sender, quantity, totalCost);
    }

    function listTicketForResale(
        uint256 ticketId,
        uint256 resalePrice,
        uint256 resaleDeadline
    ) external ticketExists(ticketId) {
        if (ownerOf(ticketId) != msg.sender) revert EventChainErrors.Unauthorized();

        EventChainTypes.Ticket storage ticket = _tickets[ticketId];

        if (ticket.isUsed) revert EventChainErrors.TicketAlreadyUsed();
        if (ticket.isForResale) revert EventChainErrors.TicketAlreadyListed();
        if (ticket.resaleCount >= MAX_RESALE_COUNT) revert EventChainErrors.ResaleLimitReached();
        if (resaleDeadline <= block.timestamp) revert EventChainErrors.InvalidDate();

        uint256 originalPrice = _ticketTypes[ticket.eventId][ticket.typeId].price;
        uint256 maxPrice = (originalPrice * MAX_RESALE_PERCENTAGE) / 100;

        if (resalePrice == 0 || resalePrice > maxPrice) {
            revert EventChainErrors.ResalePriceExceedsLimit();
        }

        ticket.isForResale = true;
        ticket.resalePrice = resalePrice;
        ticket.resaleDeadline = resaleDeadline;

        _resaleTicketIds.push(ticketId);
        _resaleTicketIndex[ticketId] = _resaleTicketIds.length - 1;

        emit TicketListedForResale(ticketId, resalePrice, resaleDeadline);
    }

    function buyResaleTicket(uint256 ticketId) external payable ticketExists(ticketId) nonReentrant {
        EventChainTypes.Ticket storage ticket = _tickets[ticketId];

        if (!ticket.isForResale) revert EventChainErrors.TicketNotForResale();
        if (msg.value != ticket.resalePrice) revert EventChainErrors.InsufficientPayment();
        if (ticket.isUsed) revert EventChainErrors.TicketAlreadyUsed();
        if (block.timestamp > ticket.resaleDeadline) revert EventChainErrors.ResaleDeadlinePassed();

        address previousOwner = ownerOf(ticketId);
        uint256 eventId = ticket.eventId;

        _processResalePayment(eventId, previousOwner, msg.value);
        _transferTicket(ticketId, previousOwner, msg.sender);

        ticket.currentOwner = msg.sender;
        ticket.isForResale = false;
        ticket.resalePrice = 0;
        ticket.resaleDeadline = 0;
        unchecked {
            ++ticket.resaleCount;
        }

        _removeFromResaleList(ticketId);

        emit TicketResold(ticketId, previousOwner, msg.sender, msg.value);
    }

    function cancelResaleListing(uint256 ticketId) external ticketExists(ticketId) {
        if (ownerOf(ticketId) != msg.sender) revert EventChainErrors.Unauthorized();

        EventChainTypes.Ticket storage ticket = _tickets[ticketId];

        if (!ticket.isForResale) revert EventChainErrors.TicketNotForResale();

        ticket.isForResale = false;
        ticket.resalePrice = 0;
        ticket.resaleDeadline = 0;

        _removeFromResaleList(ticketId);

        emit ResaleListingCancelled(ticketId);
    }

    function useTicket(uint256 ticketId, uint256 eventId)
        external
        ticketExists(ticketId)
        eventExists(eventId)
        onlyEventCreator(eventId)
    {
        EventChainTypes.Ticket storage ticket = _tickets[ticketId];

        if (ticket.eventId != eventId) revert EventChainErrors.EventNotFound();
        if (ticket.isUsed) revert EventChainErrors.TicketAlreadyUsed();

        ticket.isUsed = true;
        ticket.usedAt = block.timestamp;

        emit TicketUsed(ticketId, eventId, ticket.currentOwner);
    }

    function deactivateEvent(uint256 eventId)
        external
        eventExists(eventId)
        onlyEventCreator(eventId)
    {
        _events[eventId].eventActive = false;
        emit EventDeactivated(eventId);
    }

    function getEventDetails(uint256 eventId)
        external
        view
        eventExists(eventId)
        returns (EventChainTypes.Event memory)
    {
        return _events[eventId];
    }

    function getTicketDetails(uint256 ticketId)
        external
        view
        ticketExists(ticketId)
        returns (EventChainTypes.Ticket memory)
    {
        return _tickets[ticketId];
    }

    function getTicketType(uint256 eventId, uint256 typeId)
        external
        view
        eventExists(eventId)
        returns (EventChainTypes.TicketType memory)
    {
        return _ticketTypes[eventId][typeId];
    }

    function getEventTicketTypes(uint256 eventId)
        external
        view
        eventExists(eventId)
        returns (uint256[] memory)
    {
        return _eventTicketTypes[eventId];
    }

    function getRevenueShares(uint256 eventId)
        external
        view
        returns (EventChainTypes.RevenueShare[] memory)
    {
        return _revenueShares[eventId];
    }

    function getEOEvents(address eo) external view returns (uint256[] memory) {
        return _eoEvents[eo];
    }

    function getResaleTickets() external view returns (uint256[] memory) {
        return _resaleTicketIds;
    }

    function getUserTickets(address user) external view returns (uint256[] memory) {
        return _userTickets[user];
    }

    function getUserPurchaseCount(address user, uint256 eventId)
        external
        view
        returns (uint256)
    {
        return _userEventPurchases[user][eventId];
    }

    function canResell(uint256 ticketId)
        external
        view
        ticketExists(ticketId)
        returns (bool)
    {
        return _tickets[ticketId].resaleCount < MAX_RESALE_COUNT;
    }

    function getMaxResalePrice(uint256 ticketId)
        external
        view
        ticketExists(ticketId)
        returns (uint256)
    {
        uint256 eventId = _tickets[ticketId].eventId;
        uint256 typeId = _tickets[ticketId].typeId;
        uint256 originalPrice = _ticketTypes[eventId][typeId].price;
        return (originalPrice * MAX_RESALE_PERCENTAGE) / 100;
    }

    function isAdmin(address user) external view returns (bool) {
        return admins[user] || user == _contractOwner;
    }

    function tokenURI(uint256 ticketId)
        public
        view
        override
        ticketExists(ticketId)
        returns (string memory)
    {
        return _events[_tickets[ticketId].eventId].eventURI;
    }

    function _validatePercentages(uint256[] calldata percentages) internal pure {
        uint256 totalPercentage;
        uint256 length = percentages.length;

        for (uint256 i; i < length;) {
            totalPercentage += percentages[i];
            unchecked { ++i; }
        }

        if (totalPercentage != BASIS_POINTS) revert EventChainErrors.InvalidPercentage();
    }

    function _setupRevenueShares(
        uint256 eventId,
        address[] calldata beneficiaries,
        uint256[] calldata percentages
    ) internal {
        uint256 length = beneficiaries.length;
        for (uint256 i; i < length;) {
            _revenueShares[eventId].push(
                EventChainTypes.RevenueShare({
                    beneficiary: beneficiaries[i],
                    percentage: percentages[i]
                })
            );
            unchecked { ++i; }
        }
    }

    function _createTicket(uint256 ticketId, uint256 eventId, uint256 typeId) internal {
        _tickets[ticketId] = EventChainTypes.Ticket({
            ticketId: ticketId,
            eventId: eventId,
            typeId: typeId,
            currentOwner: msg.sender,
            isUsed: false,
            mintedAt: block.timestamp,
            usedAt: 0,
            isForResale: false,
            resalePrice: 0,
            resaleDeadline: 0,
            resaleCount: 0
        });
    }

    function _distributeRevenue(uint256 eventId, uint256 amount) internal {
        EventChainTypes.RevenueShare[] storage shares = _revenueShares[eventId];
        uint256 length = shares.length;

        for (uint256 i; i < length;) {
            uint256 share = (amount * shares[i].percentage) / BASIS_POINTS;
            _safeTransfer(shares[i].beneficiary, share);
            unchecked { ++i; }
        }
    }

    function _processResalePayment(
        uint256 eventId,
        address seller,
        uint256 amount
    ) internal {
        uint256 creatorFee = (amount * CREATOR_ROYALTY) / BASIS_POINTS;
        uint256 platformFee = (amount * PLATFORM_FEE) / BASIS_POINTS;
        uint256 sellerProceeds = amount - creatorFee - platformFee;

        _safeTransfer(_events[eventId].eventCreator, creatorFee);

        if (platformWallet != address(0)) {
            _safeTransfer(platformWallet, platformFee);
        }

        _safeTransfer(seller, sellerProceeds);
    }

    function _transferTicket(uint256 ticketId, address from, address to) internal {
        _transfer(from, to, ticketId);
        _removeFromUserTickets(from, ticketId);
        _userTickets[to].push(ticketId);
    }

    function _safeTransfer(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert EventChainErrors.TransferFailed();
    }

    function _removeFromResaleList(uint256 ticketId) internal {
        uint256 index = _resaleTicketIndex[ticketId];
        uint256 lastIndex = _resaleTicketIds.length - 1;

        if (index != lastIndex) {
            uint256 lastTicketId = _resaleTicketIds[lastIndex];
            _resaleTicketIds[index] = lastTicketId;
            _resaleTicketIndex[lastTicketId] = index;
        }

        _resaleTicketIds.pop();
        delete _resaleTicketIndex[ticketId];
    }

    function _removeFromUserTickets(address user, uint256 ticketId) internal {
        uint256[] storage userTickets = _userTickets[user];
        uint256 length = userTickets.length;

        for (uint256 i; i < length;) {
            if (userTickets[i] == ticketId) {
                userTickets[i] = userTickets[length - 1];
                userTickets.pop();
                break;
            }
            unchecked { ++i; }
        }
    }
}