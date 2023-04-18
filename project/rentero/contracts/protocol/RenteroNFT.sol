// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IRenteroNFT.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract RenteroNFT is ERC721, IRenteroNFT {
    mapping(uint256 => address) internal _tokenIdRenterMapping;
    mapping(address => uint256[]) internal _renterNFTsMapping;

    constructor(string memory name_, string memory symbol_)
        ERC721(name_, symbol_)
    {}

    function setBorrower(uint256 tokenId, address borrower)
        public
        virtual
        override
    {
        // TODO: 此处需求校验调用者权限
        require(true, "Not approved to set borrower");

        emit UpdateBorrow(tokenId, borrower);
    }

    function borrowerOf(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        return _tokenIdRenterMapping[tokenId];
    }

    function tokenListOf(address bAddress)
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        return _renterNFTsMapping[bAddress];
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceId == type(IRenteroNFT).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
