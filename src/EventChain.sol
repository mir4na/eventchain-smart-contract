// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EventChainStorage} from "./EventChainStorage.sol";
import {EventChainModifiers} from "./EventChainModifiers.sol";
import {EventChainEvents} from "./EventChainEvents.sol";
import {EventChainTypes} from "./EventChainTypes.sol";
import {EventChainErrors} from "./EventChainErrors.sol";

contract EventChain is
    ERC721,
    ReentrancyGuard,
    EventChainStorage,
    EventChainModifiers,
    EventChainEvents
{
    using ECDSA for bytes32;

    constructor(address _platformWallet, address _backendSigner)
        ERC721("EventChain Ticket", "EVTKT")
    {
        if (_platformWallet == address(0)) revert EventChainErrors.InvalidAddress();
        if (_backendSigner == address(0)) revert EventChainErrors.InvalidAddress();

        _contractOwner = msg.sender;
        platformWallet = _platformWallet;
        backendSigner = _backendSigner;
    }

    function setPlatformWallet(address wallet) external onlyOwner {
        if (wallet == address(0)) revert EventChainErrors.InvalidAddress();
        platformWallet = wallet;
        emit PlatformWalletUpdated(wallet);
    }

    function setBackendSigner(address signer) external onlyOwner {
        if (signer == address(0)) revert EventChainErrors.InvalidAddress();
        backendSigner = signer;
        emit BackendSignerUpdated(signer);
    }

    function registerEO(address eoAddress) external onlyOwner {
        if (eoAddress == address(0)) revert EventChainErrors.InvalidAddress();
        _eoAddresses[eoAddress] = true;
        emit EORegistered(eoAddress);
    }

    function removeEO(address eoAddress) external onlyOwner {
        _eoAddresses[eoAddress] = false;
        emit EORemoved(eoAddress);
    }

    function isEO(address account) external view returns (bool) {
        return _eoAddresses[account];
    }

    function configureEvent(uint256 eventId, address eventCreator, address taxWallet)
        external
        onlyOwner
        returns (bool)
    {
        if (eventCreator == address(0)) revert EventChainErrors.InvalidAddress();
        if (taxWallet == address(0)) revert EventChainErrors.InvalidAddress();
        if (_eventCreators[eventId] != address(0)) {
            revert EventChainErrors.EventAlreadyConfigured();
        }

        if (!_eoAddresses[eventCreator]) {
            _eoAddresses[eventCreator] = true;
            emit EORegistered(eventCreator);
        }

        _eventCreators[eventId] = eventCreator;
        _taxWallets[eventId] = taxWallet;
        _eventFinalized[eventId] = false;

        emit RevenueConfigured(eventId, eventCreator, taxWallet);
        return true;
    }

    function setTicketTypePrice(uint256 eventId, uint256 typeId, uint256 price)
        external
        onlyOwner
        eventConfigured(eventId)
        eventNotFinalized(eventId)
    {
        if (price == 0) revert EventChainErrors.InvalidAmount();

        _ticketTypePrices[eventId][typeId] = price;
        emit TicketTypePriceSet(eventId, typeId, price);
    }

    function finalizeEvent(uint256 eventId) external onlyOwner eventConfigured(eventId) {
        if (_eventFinalized[eventId]) revert EventChainErrors.EventAlreadyFinalized();

        _eventFinalized[eventId] = true;
        emit EventFinalized(eventId);
    }

    function buyTickets(
        uint256 eventId,
        uint256 typeId,
        uint256 quantity,
        address[] calldata beneficiaries,
        uint256[] calldata percentages
    )
        external
        payable
        nonReentrant
        eventConfigured(eventId)
        eventNotFinalized(eventId)
        withinPurchaseLimit(eventId, quantity)
        returns (uint256[] memory)
    {
        if (_eoAddresses[msg.sender]) {
            revert EventChainErrors.EOCannotBuyTickets();
        }
        if (beneficiaries.length != percentages.length) revert EventChainErrors.InvalidAmount();

        uint256 pricePerTicket = _ticketTypePrices[eventId][typeId];
        if (pricePerTicket == 0) revert EventChainErrors.TicketTypeNotConfigured();

        uint256 totalCost = pricePerTicket * quantity;
        if (msg.value < totalCost) revert EventChainErrors.InsufficientPayment();

        _validatePercentages(percentages);

        uint256 taxAmount = (totalCost * TAX_PERCENTAGE) / BASIS_POINTS;
        uint256 netAmount = totalCost - taxAmount;

        uint256[] memory ticketIds = new uint256[](quantity);

        for (uint256 i; i < quantity;) {
            unchecked {
                ++_currentTicketId;
            }
            uint256 ticketId = _currentTicketId;
            ticketIds[i] = ticketId;

            _createTicket(ticketId, eventId, typeId, pricePerTicket);
            _safeMint(msg.sender, ticketId);
            _userTickets[msg.sender].push(ticketId);

            emit TicketMinted(ticketId, eventId, typeId, msg.sender, pricePerTicket);

            unchecked {
                ++i;
            }
        }

        _userEventTicketCount[msg.sender][eventId] += quantity;

        _distributeRevenue(eventId, taxAmount, netAmount, beneficiaries, percentages);

        if (msg.value > totalCost) {
            uint256 refund = msg.value - totalCost;
            (bool success,) = payable(msg.sender).call{value: refund}("");
            if (!success) revert EventChainErrors.TransferFailed();
        }

        emit TicketsPurchased(
            eventId, typeId, msg.sender, quantity, totalCost, taxAmount, ticketIds
        );
        return ticketIds;
    }

    function listTicketForResale(uint256 ticketId, uint256 resalePrice, uint256 resaleDeadline)
        external
        ticketExists(ticketId)
    {
        if (ownerOf(ticketId) != msg.sender) revert EventChainErrors.Unauthorized();

        EventChainTypes.Ticket storage ticket = _tickets[ticketId];

        if (ticket.isUsed) revert EventChainErrors.TicketAlreadyUsed();
        if (ticket.isForResale) revert EventChainErrors.TicketAlreadyListed();
        if (ticket.resaleCount >= 1) revert EventChainErrors.ResaleLimitReached();
        if (resaleDeadline <= block.timestamp) revert EventChainErrors.InvalidDate();

        uint256 maxPrice = (ticket.originalPrice * MAX_RESALE_PERCENTAGE) / 100;
        if (resalePrice == 0 || resalePrice > maxPrice) {
            revert EventChainErrors.ResalePriceExceedsLimit();
        }

        ticket.isForResale = true;
        ticket.resalePrice = resalePrice;
        ticket.resaleDeadline = resaleDeadline;

        _resaleTicketIds.push(ticketId);
        _resaleTicketIndex[ticketId] = _resaleTicketIds.length - 1;

        emit TicketListedForResale(
            ticketId, ticket.eventId, msg.sender, resalePrice, resaleDeadline
        );
    }

    function buyResaleTicket(uint256 ticketId)
        external
        payable
        ticketExists(ticketId)
        nonReentrant
    {
        if (_eoAddresses[msg.sender]) revert EventChainErrors.EOCannotBuyTickets();

        EventChainTypes.Ticket storage ticket = _tickets[ticketId];

        if (!ticket.isForResale) revert EventChainErrors.TicketNotForResale();
        if (msg.value != ticket.resalePrice) revert EventChainErrors.InsufficientPayment();
        if (ticket.isUsed) revert EventChainErrors.TicketAlreadyUsed();
        if (block.timestamp > ticket.resaleDeadline) {
            revert EventChainErrors.ResaleDeadlinePassed();
        }

        address previousOwner = ownerOf(ticketId);
        uint256 eventId = ticket.eventId;

        uint256 taxAmount = (msg.value * TAX_PERCENTAGE) / BASIS_POINTS;
        uint256 netAmount = msg.value - taxAmount;

        _processResalePayment(eventId, previousOwner, taxAmount, netAmount);
        _transferTicket(ticketId, previousOwner, msg.sender);

        ticket.currentOwner = msg.sender;
        ticket.isForResale = false;
        ticket.resalePrice = 0;
        ticket.resaleDeadline = 0;
        unchecked {
            ++ticket.resaleCount;
        }

        _removeFromResaleList(ticketId);

        emit TicketResold(ticketId, eventId, previousOwner, msg.sender, msg.value, taxAmount);
    }

    function cancelResaleListing(uint256 ticketId) external ticketExists(ticketId) {
        if (ownerOf(ticketId) != msg.sender) revert EventChainErrors.Unauthorized();

        EventChainTypes.Ticket storage ticket = _tickets[ticketId];
        if (!ticket.isForResale) revert EventChainErrors.TicketNotForResale();

        ticket.isForResale = false;
        ticket.resalePrice = 0;
        ticket.resaleDeadline = 0;

        _removeFromResaleList(ticketId);

        emit ResaleListingCancelled(ticketId, msg.sender);
    }

    function useTicket(
        uint256 ticketId,
        uint256 eventId,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external ticketExists(ticketId) {
        EventChainTypes.Ticket storage ticket = _tickets[ticketId];

        if (ticket.eventId != eventId) revert EventChainErrors.InvalidEvent();
        if (ticket.isUsed) revert EventChainErrors.TicketAlreadyUsed();
        if (block.timestamp > deadline) revert EventChainErrors.SignatureExpired();
        if (_usedNonces[ticketId][nonce]) revert EventChainErrors.NonceAlreadyUsed();

        _verifyBackendSignature(ticketId, eventId, msg.sender, nonce, deadline, signature);

        ticket.isUsed = true;
        ticket.usedAt = block.timestamp;
        _usedNonces[ticketId][nonce] = true;

        emit TicketUsed(ticketId, eventId, ticket.currentOwner, block.timestamp);
    }

    function withdraw() external nonReentrant {
        uint256 amount = _pendingWithdrawals[msg.sender];
        if (amount == 0) revert EventChainErrors.NoBalanceToWithdraw();

        _pendingWithdrawals[msg.sender] = 0;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            _pendingWithdrawals[msg.sender] = amount;
            revert EventChainErrors.TransferFailed();
        }

        emit Withdrawn(msg.sender, amount);
    }

    function setTokenURI(uint256 ticketId, string calldata uri)
        external
        onlyOwner
        ticketExists(ticketId)
    {
        _tokenURIs[ticketId] = uri;
        emit TokenURIUpdated(ticketId, uri);
    }

    function tokenURI(uint256 ticketId)
        public
        view
        override
        ticketExists(ticketId)
        returns (string memory)
    {
        return _tokenURIs[ticketId];
    }

    function getTicketDetails(uint256 ticketId)
        external
        view
        ticketExists(ticketId)
        returns (EventChainTypes.Ticket memory)
    {
        return _tickets[ticketId];
    }

    function getResaleTickets() external view returns (uint256[] memory) {
        return _resaleTicketIds;
    }

    function getUserTickets(address user) external view returns (uint256[] memory) {
        return _userTickets[user];
    }

    function getUserEventTicketCount(address user, uint256 eventId)
        external
        view
        returns (uint256)
    {
        return _userEventTicketCount[user][eventId];
    }

    function getPendingWithdrawal(address user) external view returns (uint256) {
        return _pendingWithdrawals[user];
    }

    function getTicketTypePrice(uint256 eventId, uint256 typeId) external view returns (uint256) {
        return _ticketTypePrices[eventId][typeId];
    }

    function canResell(uint256 ticketId) external view ticketExists(ticketId) returns (bool) {
        return _tickets[ticketId].resaleCount < 1 && !_tickets[ticketId].isUsed;
    }

    function getMaxResalePrice(uint256 ticketId)
        external
        view
        ticketExists(ticketId)
        returns (uint256)
    {
        return (_tickets[ticketId].originalPrice * MAX_RESALE_PERCENTAGE) / 100;
    }

    function getEventCreator(uint256 eventId) external view returns (address) {
        return _eventCreators[eventId];
    }

    function isEventFinalized(uint256 eventId) external view returns (bool) {
        return _eventFinalized[eventId];
    }

    function _validatePercentages(uint256[] calldata percentages) internal pure {
        uint256 totalPercentage;
        uint256 length = percentages.length;

        for (uint256 i; i < length;) {
            totalPercentage += percentages[i];
            unchecked {
                ++i;
            }
        }

        if (totalPercentage != BASIS_POINTS) revert EventChainErrors.InvalidAmount();
    }

    function _createTicket(uint256 ticketId, uint256 eventId, uint256 typeId, uint256 price)
        internal
    {
        _tickets[ticketId] = EventChainTypes.Ticket({
            ticketId: ticketId,
            eventId: eventId,
            typeId: typeId,
            currentOwner: msg.sender,
            originalPrice: price,
            isUsed: false,
            mintedAt: block.timestamp,
            usedAt: 0,
            isForResale: false,
            resalePrice: 0,
            resaleDeadline: 0,
            resaleCount: 0
        });
    }

    function _distributeRevenue(
        uint256 eventId,
        uint256 taxAmount,
        uint256 netAmount,
        address[] calldata beneficiaries,
        uint256[] calldata percentages
    ) internal {
        address taxWallet = _taxWallets[eventId];
        _pendingWithdrawals[taxWallet] += taxAmount;

        uint256 length = beneficiaries.length;
        for (uint256 i; i < length;) {
            uint256 share = (netAmount * percentages[i]) / BASIS_POINTS;
            _pendingWithdrawals[beneficiaries[i]] += share;
            unchecked {
                ++i;
            }
        }

        emit RevenueDistributed(eventId, msg.value, taxAmount, netAmount, block.timestamp);
    }

    function _processResalePayment(
        uint256 eventId,
        address seller,
        uint256 taxAmount,
        uint256 netAmount
    ) internal {
        address taxWallet = _taxWallets[eventId];
        address creator = _eventCreators[eventId];

        _pendingWithdrawals[taxWallet] += taxAmount;

        uint256 creatorFee = (netAmount * CREATOR_ROYALTY) / BASIS_POINTS;
        uint256 platformFee = (netAmount * PLATFORM_FEE) / BASIS_POINTS;
        uint256 sellerProceeds = netAmount - creatorFee - platformFee;

        _pendingWithdrawals[creator] += creatorFee;

        if (platformWallet != address(0)) {
            _pendingWithdrawals[platformWallet] += platformFee;
        }

        _pendingWithdrawals[seller] += sellerProceeds;
    }

    function _transferTicket(uint256 ticketId, address from, address to) internal {
        _transfer(from, to, ticketId);
        _removeFromUserTickets(from, ticketId);
        _userTickets[to].push(ticketId);
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
            unchecked {
                ++i;
            }
        }
    }

    function _verifyBackendSignature(
        uint256 ticketId,
        uint256 eventId,
        address scanner,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) internal view {
        bytes32 messageHash = keccak256(
            abi.encodePacked(ticketId, eventId, scanner, nonce, deadline, block.chainid)
        );

        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recover(ethSignedMessageHash, signature);

        if (recoveredSigner != backendSigner) {
            revert EventChainErrors.InvalidSignature();
        }
    }
}
