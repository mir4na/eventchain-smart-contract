// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract EventChain is ERC721, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    // ============ Constructor ============
    constructor() ERC721("EventChain Ticket", "EVTKT") {}

    // ============ State Variables ============
    Counters.Counter private _eventIdCounter;
    Counters.Counter private _ticketIdCounter;

    struct Event {
        uint256 eventId;
        address eventCreator;
        string eventName;
        string eventURI; // IPFS metadata
        uint256 ticketPrice;
        uint256 totalTickets;
        uint256 ticketsSold;
        uint256 eventDate;
        bool eventActive;
        uint256 createdAt;
    }

    struct RentalRevenue {
        address beneficiary;
        uint256 percentage;
    }

    struct Ticket {
        uint256 ticketId;
        uint256 eventId;
        address currentOwner;
        bool isUsed;
        uint256 mintedAt;
    }

    mapping(uint256 => Event) public events;
    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => RentalRevenue[]) public revenueShares; // eventId => array of revenue splits
    mapping(uint256 => uint256) public ticketResalePrice; // ticketId => resale price
    mapping(uint256 => bool) public ticketForSale; // ticketId => is listed for resale

    // Events
    event EventCreated(uint256 indexed eventId, address indexed creator, string eventName, uint256 ticketPrice);
    event TicketMinted(uint256 indexed ticketId, uint256 indexed eventId, address indexed buyer);
    event TicketUsed(uint256 indexed ticketId, uint256 indexed eventId);
    event TicketListedForResale(uint256 indexed ticketId, uint256 resalePrice);
    event TicketResold(uint256 indexed ticketId, address indexed from, address indexed to, uint256 price);
    event RevenueClaimed(address indexed beneficiary, uint256 amount);

    // ============ Modifiers (wrapping logic into internal functions) ============
    modifier eventExists(uint256 eventId) {
        _eventExists(eventId);
        _;
    }

    modifier onlyEventCreator(uint256 eventId) {
        _onlyEventCreator(eventId);
        _;
    }

    modifier ticketExists(uint256 ticketId) {
        _ticketExists(ticketId);
        _;
    }

    // Internal checks (helps reduce duplicate bytecode and follow forge-lint suggestion)
    function _eventExists(uint256 eventId) internal view {
        require(events[eventId].eventId != 0, "Event tidak ditemukan");
    }

    function _onlyEventCreator(uint256 eventId) internal view {
        require(msg.sender == events[eventId].eventCreator, "Hanya kreator event yang bisa aksi ini");
    }

    function _ticketExists(uint256 ticketId) internal view {
        require(tickets[ticketId].ticketId != 0, "Tiket tidak ditemukan");
    }

    // ============ Create Event ============
    function createEvent(
        string memory eventName,
        string memory eventURI,
        uint256 ticketPrice,
        uint256 totalTickets,
        uint256 eventDate,
        address[] memory revenueBeneficiaries,
        uint256[] memory percentages
    ) external returns (uint256) {
        require(ticketPrice > 0, "Harga tiket harus > 0");
        require(totalTickets > 0, "Total tiket harus > 0");
        require(eventDate > block.timestamp, "Event date harus di masa depan");
        require(revenueBeneficiaries.length == percentages.length, "Jumlah beneficiary dan percentage harus sama");

        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < percentages.length; i++) {
            totalPercentage += percentages[i];
        }
        require(totalPercentage == 10000, "Total percentage harus 100% (10000 basis points)");

        _eventIdCounter.increment();
        uint256 newEventId = _eventIdCounter.current();

        events[newEventId] = Event({
            eventId: newEventId,
            eventCreator: msg.sender,
            eventName: eventName,
            eventURI: eventURI,
            ticketPrice: ticketPrice,
            totalTickets: totalTickets,
            ticketsSold: 0,
            eventDate: eventDate,
            eventActive: true,
            createdAt: block.timestamp
        });

        // Setup revenue sharing (use named struct fields for clarity)
        for (uint256 i = 0; i < revenueBeneficiaries.length; i++) {
            revenueShares[newEventId].push(
                RentalRevenue({
                    beneficiary: revenueBeneficiaries[i],
                    percentage: percentages[i]
                })
            );
        }

        emit EventCreated(newEventId, msg.sender, eventName, ticketPrice);
        return newEventId;
    }

    // ============ Buy Ticket ============
    function buyTicket(uint256 eventId) external payable eventExists(eventId) nonReentrant {
        Event storage eventData = events[eventId];
        require(eventData.eventActive, "Event tidak aktif");
        require(eventData.ticketsSold < eventData.totalTickets, "Tiket habis");
        require(msg.value == eventData.ticketPrice, "Nilai ETH tidak sesuai");

        _ticketIdCounter.increment();
        uint256 newTicketId = _ticketIdCounter.current();

        tickets[newTicketId] = Ticket({
            ticketId: newTicketId,
            eventId: eventId,
            currentOwner: msg.sender,
            isUsed: false,
            mintedAt: block.timestamp
        });

        _safeMint(msg.sender, newTicketId);
        eventData.ticketsSold++;

        // Distribute revenue otomatis
        _distributeRevenue(eventId, msg.value);

        emit TicketMinted(newTicketId, eventId, msg.sender);
    }

    // ============ Revenue Distribution (Internal) ============
    function _distributeRevenue(uint256 eventId, uint256 amount) internal {
        RentalRevenue[] storage shares = revenueShares[eventId];
        for (uint256 i = 0; i < shares.length; i++) {
            uint256 share = (amount * shares[i].percentage) / 10000;
            (bool success, ) = payable(shares[i].beneficiary).call{value: share}("");
            require(success, "Transfer revenue gagal");
        }
    }

    // ============ Resale Ticket ============
    function listTicketForResale(uint256 ticketId, uint256 resalePrice) external ticketExists(ticketId) {
        require(ownerOf(ticketId) == msg.sender, "Kamu bukan pemilik tiket");
        require(!tickets[ticketId].isUsed, "Tiket yang sudah dipakai tidak bisa dijual");
        require(resalePrice > 0, "Harga resale harus > 0");

        ticketResalePrice[ticketId] = resalePrice;
        ticketForSale[ticketId] = true;

        emit TicketListedForResale(ticketId, resalePrice);
    }

    function buyResaleTicket(uint256 ticketId) external payable ticketExists(ticketId) nonReentrant {
        require(ticketForSale[ticketId], "Tiket tidak tersedia untuk dijual");
        require(msg.value == ticketResalePrice[ticketId], "Nilai ETH tidak sesuai");
        require(!tickets[ticketId].isUsed, "Tiket sudah dipakai");

        Ticket storage ticket = tickets[ticketId];
        uint256 eventId = ticket.eventId;
        address previousOwner = ownerOf(ticketId);

        // Royalty split untuk kreator event dan pemilik sebelumnya
        uint256 creatorRoyalty = (msg.value * 20) / 100; // 20% untuk kreator event
        uint256 sellerProceeds = msg.value - creatorRoyalty;

        (bool creatorSuccess, ) = payable(events[eventId].eventCreator).call{value: creatorRoyalty}("");
        require(creatorSuccess, "Transfer royalty gagal");

        (bool sellerSuccess, ) = payable(previousOwner).call{value: sellerProceeds}("");
        require(sellerSuccess, "Transfer ke penjual gagal");

        // Transfer NFT
        _transfer(previousOwner, msg.sender, ticketId);
        ticket.currentOwner = msg.sender;

        ticketForSale[ticketId] = false;

        emit TicketResold(ticketId, previousOwner, msg.sender, msg.value);
    }

    // ============ Use Ticket (Event Organizer) ============
    function useTicket(uint256 ticketId, uint256 eventId) 
        external 
        ticketExists(ticketId) 
        eventExists(eventId)
        onlyEventCreator(eventId)
    {
        Ticket storage ticket = tickets[ticketId];
        require(ticket.eventId == eventId, "Tiket bukan dari event ini");
        require(!ticket.isUsed, "Tiket sudah dipakai");

        ticket.isUsed = true;

        emit TicketUsed(ticketId, eventId);
    }

    // ============ Deactivate Event ============
    function deactivateEvent(uint256 eventId) external eventExists(eventId) onlyEventCreator(eventId) {
        events[eventId].eventActive = false;
    }

    // ============ View Functions ============
    function getEventDetails(uint256 eventId) external view eventExists(eventId) returns (Event memory) {
        return events[eventId];
    }

    function getTicketDetails(uint256 ticketId) external view ticketExists(ticketId) returns (Ticket memory) {
        return tickets[ticketId];
    }

    function getRevenueShares(uint256 eventId) external view returns (RentalRevenue[] memory) {
        return revenueShares[eventId];
    }

    function getTicketURI(uint256 ticketId) external view ticketExists(ticketId) returns (string memory) {
        return events[tickets[ticketId].eventId].eventURI;
    }

    // ============ Compliance ============
    function tokenURI(uint256 ticketId) public view override ticketExists(ticketId) returns (string memory) {
        Ticket memory ticket = tickets[ticketId];
        return events[ticket.eventId].eventURI;
    }
}
