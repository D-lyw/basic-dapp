//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0 


// 委托投票  
contract Ballot {
    
    struct Voter {
        uint weight;
        bool isVoted;
        address delegate;
        uint vote;
    }
    
    struct Proposal {
        bytes32 name;
        uint256 voteCount;
    }
    
    address public chairperson;
    
    mapping(address => Voter) public voters;
    
    Proposal[] public proposals;
    
    constructor(bytes32[] memory proposalNames) {
        chairperson = msg.sender;
        voters[chairperson].weight = 1;
        
        for(uint i = 0; i < proposalNames.length; i++) {
            proposals.push(Proposal({
                name: proposalNames[i].name,
                voteCount: 0
            }))
        }
    }
    
    function giveVoteRight(address voter) public {
        require(msg.sender == chairperson, "not chairpseron");
        require(!voters[voter].isVoted);
        voters[voter].weight = 1;
    } 

    function delegateVote(address to) public {
		Voter storage sender = voters[msg.sender];
		require(!sender.isVoted);
		require(to != msg.sender);

		while (voters[to].delegate != address(0)) {
			to = voters[to].delegate;

			// 不允许循环委托
			require(to != msg.sender);
		}

		sender.isVoted = true;
		sender.delegate = to;

		Voter storage delegate_ = voters[to];
		if (delegate_.isVoted) {
			proposal[delegate_.vote].voteCount += sender.weight;
		} else {
			delegate_.weight += sender.weight;
		}
    }

	function voteProposal(uint proposal) public {
		Voter storage sender = voters[msg.sender];
		require(!sender.isVoted);
		sender.isVoted = true;
		sender.vote = proposal;

		proposals[proposal].voteCount += sender.weight;
	}

	function winningProposal() public view return (uint winingProposal_) {
		uint winingVoteCount = 0;
		for (uint p = 0; p < proposals.length; p++) {
			if (proposals[p].voteCount > winingVoteCount) {
				winingVoteCount proposals[p].voteCount;
				winingProposal_ = p
			}
		}
	}

	function winnerName() public view return (bytes32 winnerName_){
		winnerName_ = proposals[winingProposal()].name;
	}
}