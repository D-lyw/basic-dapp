//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract AXE is ERC721, Ownable {
    using Strings for uint256;
    using Counters for Counters.Counter;

    string _baseTokenURI;
    Counters.Counter _tokenIds;

    uint256 public MAX_SUPPLY = 90;

    constructor() ERC721("AXE-GAEM", "Axe") {
        _baseTokenURI = "https://gateway.pinata.cloud/ipfs/QmfXXHoYcCV682xv5yvziqqEsi3gHN1WftxYyyt5c8M1Tt/";
    }

    function mint() public {
        uint256 tokenId = totalSupply() + 1;
        require(tokenId <= MAX_SUPPLY, "Max supply exceeded");
        _safeMint(msg.sender, tokenId);
        _tokenIds.increment();
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIds.current();
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "URI query for nonexistent token");
        return
            string(
                abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json")
            );
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        _baseTokenURI = _newBaseURI;
    }
}
