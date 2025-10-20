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

    mapping(address => bool) public admins;
    mapping(address => bool) public approvedEOs;

    struct Event {
        uint256 eventId;
        address eventCreator;
        string eventName;
        string eventURI;
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
        bool isForResale;
        uint256 resalePrice;
        uint256 resaleDeadline;
    }

    mapping(uint256 => Event) public events;
    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => RentalRevenue[]) public revenueShares;
    mapping(uint256 => uint256) public ticketResalePrice;
    mapping(uint256 => bool) public ticketForSale;
    mapping(uint256 => uint256) public ticketResaleDeadline;

    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event EOApproved(address indexed eo);
    event EventCreated(uint256 indexed eventId, address indexed creator, string eventName, uint256 ticketPrice);
    event TicketMinted(uint256 indexed ticketId, uint256 indexed eventId, address indexed buyer);
    event TicketUsed(uint256 indexed ticketId, uint256 indexed eventId);
    event TicketListedForResale(uint256 indexed ticketId, uint256 resalePrice, uint256 deadline);
    event TicketResold(uint256 indexed ticketId, address indexed from, address indexed to, uint256 price);
    event RevenueClaimed(address indexed beneficiary, uint256 amount);

    // ============ Modifiers ============
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyApprovedEo() {
        _onlyApprovedEo();
        _;
    }

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

    function _onlyAdmin() internal view {
        require(admins[msg.sender] || msg.sender == owner(), "Only admin");
    }

    function _onlyApprovedEo() internal view {
        require(approvedEOs[msg.sender], "EO not approved");
    }

    function _eventExists(uint256 eventId) internal view {
        require(events[eventId].eventId != 0, "Event tidak ditemukan");
    }

    function _onlyEventCreator(uint256 eventId) internal view {
        require(msg.sender == events[eventId].eventCreator, "Hanya kreator event");
    }

    function _ticketExists(uint256 ticketId) internal view {
        require(tickets[ticketId].ticketId != 0, "Tiket tidak ditemukan");
    }

    // ============ Admin Functions ============
    function addAdmin(address _admin) external onlyOwner {
        admins[_admin] = true;
        emit AdminAdded(_admin);
    }

    function removeAdmin(address _admin) external onlyOwner {
        admins[_admin] = false;
        emit AdminRemoved(_admin);
    }

    function approveEo(address _eo) external onlyAdmin {
        approvedEOs[_eo] = true;
        emit EOApproved(_eo);
    }

    function revokeEo(address _eo) external onlyAdmin {
        approvedEOs[_eo] = false;
    }

    // ============ Create Event (Only Approved EO) ============
    function createEvent(
        string memory eventName,
        string memory eventURI,
        uint256 ticketPrice,
        uint256 totalTickets,
        uint256 eventDate,
        address[] memory revenueBeneficiaries,
        uint256[] memory percentages
    ) external onlyApprovedEo returns (uint256) {
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
            mintedAt: block.timestamp,
            isForResale: false,
            resalePrice: 0,
            resaleDeadline: 0
        });

        _safeMint(msg.sender, newTicketId);
        eventData.ticketsSold++;

        _distributeRevenue(eventId, msg.value);

        emit TicketMinted(newTicketId, eventId, msg.sender);
    }

    // ============ Revenue Distribution ============
    function _distributeRevenue(uint256 eventId, uint256 amount) internal {
        RentalRevenue[] storage shares = revenueShares[eventId];
        for (uint256 i = 0; i < shares.length; i++) {
            uint256 share = (amount * shares[i].percentage) / 10000;
            (bool success, ) = payable(shares[i].beneficiary).call{value: share}("");
            require(success, "Transfer revenue gagal");
        }
    }

    // ============ Resale Ticket (with Deadline) ============
    function listTicketForResale(
        uint256 ticketId, 
        uint256 resalePrice,
        uint256 resaleDeadline
    ) external ticketExists(ticketId) {
        require(ownerOf(ticketId) == msg.sender, "Bukan pemilik tiket");
        require(!tickets[ticketId].isUsed, "Tiket sudah dipakai");
        require(resalePrice > 0, "Harga resale harus > 0");
        require(resaleDeadline > block.timestamp, "Deadline harus di masa depan");

        Ticket storage ticket = tickets[ticketId];
        ticket.isForResale = true;
        ticket.resalePrice = resalePrice;
        ticket.resaleDeadline = resaleDeadline;

        ticketResalePrice[ticketId] = resalePrice;
        ticketForSale[ticketId] = true;
        ticketResaleDeadline[ticketId] = resaleDeadline;

        emit TicketListedForResale(ticketId, resalePrice, resaleDeadline);
    }

    function buyResaleTicket(uint256 ticketId) external payable ticketExists(ticketId) nonReentrant {
        Ticket storage ticket = tickets[ticketId];
        
        require(ticket.isForResale, "Tiket tidak tersedia untuk dijual");
        require(msg.value == ticket.resalePrice, "Nilai ETH tidak sesuai");
        require(!ticket.isUsed, "Tiket sudah dipakai");
        require(block.timestamp <= ticket.resaleDeadline, "Deadline resale sudah lewat");

        uint256 eventId = ticket.eventId;
        address previousOwner = ownerOf(ticketId);

        uint256 creatorRoyalty = (msg.value * 20) / 100;
        uint256 sellerProceeds = msg.value - creatorRoyalty;

        (bool creatorSuccess, ) = payable(events[eventId].eventCreator).call{value: creatorRoyalty}("");
        require(creatorSuccess, "Transfer royalty gagal");

        (bool sellerSuccess, ) = payable(previousOwner).call{value: sellerProceeds}("");
        require(sellerSuccess, "Transfer ke penjual gagal");

        _transfer(previousOwner, msg.sender, ticketId);
        ticket.currentOwner = msg.sender;
        ticket.isForResale = false;
        ticket.resalePrice = 0;
        ticket.resaleDeadline = 0;

        ticketForSale[ticketId] = false;

        emit TicketResold(ticketId, previousOwner, msg.sender, msg.value);
    }

    // ============ Cancel Resale Listing ============
    function cancelResaleListing(uint256 ticketId) external ticketExists(ticketId) {
        require(ownerOf(ticketId) == msg.sender, "Bukan pemilik tiket");
        
        Ticket storage ticket = tickets[ticketId];
        ticket.isForResale = false;
        ticket.resalePrice = 0;
        ticket.resaleDeadline = 0;
        
        ticketForSale[ticketId] = false;
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

    function isEoApproved(address eo) external view returns (bool) {
        return approvedEOs[eo];
    }

    function isAdmin(address user) external view returns (bool) {
        return admins[user] || user == owner();
    }

    function getResaleTickets() external view returns (uint256[] memory) {
        uint256 totalTickets = _ticketIdCounter.current();
        uint256 resaleCount = 0;

        for (uint256 i = 1; i <= totalTickets; i++) {
            if (tickets[i].isForResale && block.timestamp <= tickets[i].resaleDeadline) {
                resaleCount++;
            }
        }

        uint256[] memory resaleTickets = new uint256[](resaleCount);
        uint256 index = 0;

        for (uint256 i = 1; i <= totalTickets; i++) {
            if (tickets[i].isForResale && block.timestamp <= tickets[i].resaleDeadline) {
                resaleTickets[index] = i;
                index++;
            }
        }

        return resaleTickets;
    }

    function getUserTickets(address user) external view returns (uint256[] memory) {
        uint256 totalTickets = _ticketIdCounter.current();
        uint256 userTicketCount = 0;

        for (uint256 i = 1; i <= totalTickets; i++) {
            if (ownerOf(i) == user) {
                userTicketCount++;
            }
        }

        uint256[] memory userTickets = new uint256[](userTicketCount);
        uint256 index = 0;

        for (uint256 i = 1; i <= totalTickets; i++) {
            if (ownerOf(i) == user) {
                userTickets[index] = i;
                index++;
            }
        }

        return userTickets;
    }

    // ============ Compliance ============
    function tokenURI(uint256 ticketId) public view override ticketExists(ticketId) returns (string memory) {
        Ticket memory ticket = tickets[ticketId];
        return events[ticket.eventId].eventURI;
    }
}