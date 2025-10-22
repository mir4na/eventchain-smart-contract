# MyMineTicketKu — Smart Contracts

This repository contains the Solidity smart contracts powering the MyMineTicketKu decentralized NFT ticketing platform. Built with Foundry and OpenZeppelin, the contracts support secure event creation, NFT-based ticketing, anti-scalping mechanisms, and automatic revenue distribution.

## 🏗️ Tech Stack

- **Language**: Solidity ^0.8.30
- **Libraries**: OpenZeppelin (ERC721, ReentrancyGuard, AccessControl)
- **Tooling**: Foundry (Forge, Cast, Anvil)
- **Testing**: Forge test suite

## 🎫 Core Features

### Event & Ticket Management
- Event organizers (EOs) create events with configurable ticket types (Regular, VIP, etc.)  
- Each ticket is an ERC721 NFT (unique, collectible, transferable)  

### Anti-Scalping & Resale Rules
- Max **5 tickets per user per event**  
- Resale allowed **only once** per ticket  
- Resale price capped at **120%** of original price  
- Resale listings expire after a deadline set by seller  

### Revenue Distribution (on resale)
- **5% royalty** to Event Organizer  
- **2.5% platform fee**  
- Enforced via ERC721 royalty mechanism (**500 + 250 basis points**)  

### Security
- Reentrancy protection (`ReentrancyGuard`)  
- Role-based access control (`AccessControl`)  
- Input validation  
- Emergency stop capability  