// SPDX-License-Identifier: MIT
// origin aritcle link: https://medium.com/coinmonks/solidity-merkle-tree-41c2d2b1071f
pragma solidity ^0.8.0;

contract MerkleTree {
    //          ROOT
    //        /      \
    //    H1-2        H3-4
    //    /  \        /  \
    //  H1    H2    H3    H4
    //   |     |     |     |
    //  TX1   TX2   TX3   TX4

    bytes32[] public hashes;
    string[4] transactions = [
        "TX1: Scherlock -> John",
        "TX2: John -> Sherlock",
        "TX3: John -> Mary",
        "TX4: Mary -> Sherlock"
    ];

    constructor() {
        for (uint i = 0; i < transactions.length; i++) {
            hashes.push(makeHash(transactions[i])); // H1 H2 H3 H4
        }

        uint count = transactions.length; // number of leaves
        uint offset = 0;

        while (count > 0) {
            for (uint i = 0; i < count - 1; i += 2) {
                hashes.push(
                    keccak256(
                        abi.encodePacked(
                            hashes[offset + i],
                            hashes[offset + i + 1]
                        )
                    )
                );
            }
            offset += count;
            count = count / 2;
        }
    }

    function verify(
        string memory transaction,
        uint index,
        bytes32 root,
        bytes32[] memory proof
    ) public pure returns (bool) {
        bytes32 hash = makeHash(transaction); // get hash transactions for check
        for (uint i = 0; i < proof.length; i++) {
            bytes32 element = proof[i];
            if (index % 2 == 0) {
                hash = keccak256(abi.encodePacked(hash, element));
            } else {
                hash = keccak256(abi.encodePacked(element, hash));
            }
            index = index / 2;
        }
        return hash == root;
    }

    function makeHash(string memory input) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(input));
    }
}
