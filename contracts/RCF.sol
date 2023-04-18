// https://bscscan.com/address/0x999017cB5652Caf5f324A8E44F813903ba3C46Eb#code
// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract NFT is ERC721, Ownable  {
    using Counters for Counters.Counter;
    using ECDSA for bytes32;
    address private _signer;
    string private _image;
    
    mapping(uint256  => string) private dataList; // tid to metadata
    mapping(uint256  => Metadata) private metadataList; // tid to metadata
    struct Metadata {
        address minter;
        address receiver;
        uint tsp;
        bytes32 hash;
    }
    
    // Basic ERC721
    Counters.Counter _tokenIds;

    constructor(address signer, string memory image) ERC721("CheersBio Capsule", "CBC") {
        _signer = signer;
        _image = image;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _tokenIds.current();
    }

    // Mint Logic
    function mint(address receiver, bytes32 mHash, uint tsp, uint expiry, bytes memory sig) public  {
        require(block.timestamp < expiry, "Token has expired.");
        require(_verify(_hash(receiver, mHash, tsp, expiry), sig), "Invalid token");
        
        uint256 tokenId = totalSupply() + 1;
        
        Metadata storage m = metadataList[tokenId];
        m.minter = msg.sender;
        m.receiver = receiver;
        m.tsp = tsp;
        m.hash = mHash;

        _safeMint(receiver, tokenId);
        _tokenIds.increment();
    }

    function unlock(uint256 tokenId, string memory data) public {
        require(_exists(tokenId), "Token id does not exist.");
        require(block.timestamp >= metadataList[tokenId].tsp, "Unlock is not ready.");
        require(keccak256(bytes(data)) == metadataList[tokenId].hash, "Decrpted data is wrong.");
        dataList[tokenId] = data;
    }
    
  
    function tokenURI(uint256 tokenId)  view public override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        Metadata memory m = metadataList[tokenId];
        // bytes32 hash =  hashList[tokenId];
        string memory description = "";
        if(bytes(dataList[tokenId]).length == 0){
            description = "--- Unlocked yet. ---";
        } else {
            description = dataList[tokenId];
        }
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "RSS3 Chain Friends #',
                        Strings.toString(tokenId),
                        '", "description": "',
                        description,
                        '", "image": "',
                        _image,
                        '", "traits": [{"trait_type": "UnblockDates", "value": "',
                        Strings.toString(m.tsp),
                        '"}, {"trait_type": "From", "value": " ',
                        toAsciiString(m.minter),
                        '"}, {"trait_type": "To", "value": "' ,
                        toAsciiString(m.receiver),
                        '"}]',
                        '}'
                    )
                )
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    // Verify Logic
    function _hash(address _address, bytes32 m, uint tsp, uint expiry) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(_address, m, tsp, expiry, address(this)));
    }

    function _verify(bytes32 hash, bytes memory sig) internal view returns (bool) {
        return (_recover(hash, sig) == _signer);
    }

    function _recover(bytes32 hash, bytes memory sig) internal pure returns (address) {
        return hash.toEthSignedMessageHash().recover(sig);
    }

    function setSigner(address account) public onlyOwner {
        _signer = account;
    }

    function setImage(string memory image) public onlyOwner {
        _image = image;
    }

    // utils
    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);            
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}