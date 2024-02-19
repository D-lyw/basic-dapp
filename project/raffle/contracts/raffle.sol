// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

// https://docs.chain.link/vrf/v2/getting-started#contract-variables

contract Raffle is Ownable, VRFConsumerBaseV2 {
    mapping(address => int) public addressList;
    address[] public winList;

    uint64 private _subscriptionId;
    address private immutable _vrfCoordinator;

    mapping(uint256 => uint256) vrfResMap;
    uint256 private _randomWords;

    event RandomWordsRequested(uint256 requestId);
    event RandomWrodsFulfilled(uint256 requestId, uint256 randomWords);

    constructor(
        address vrfCoordinator,
        uint64 subscriptionId
    ) Ownable(msg.sender) VRFConsumerBaseV2(vrfCoordinator) {
        _vrfCoordinator = vrfCoordinator;
        _subscriptionId = subscriptionId;
    }

    function raffleWinList() public onlyOwner {}

    function requestRandomWords(bytes32 keyHash, uint32 callbackGasLimit ) public onlyOwner {
        uint256 requestId = VRFCoordinatorV2Interface(_vrfCoordinator).requestRandomWords(keyHash,
        _subscriptionId,
        3,
        callbackGasLimit,
        1);

        emit RandomWordsRequested(requestId);
    }

    function updateVRFSubId(uint64 subscriptionId) public onlyOwner {
        _subscriptionId = subscriptionId;
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal virtual override {
        vrfResMap[requestId] = randomWords[0];
        _randomWords = randomWords[0];

        emit RandomWrodsFulfilled(requestId, randomWords[0]);
    }
}
