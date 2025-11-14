// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

// interface pour exposer les stats H/F
interface IVotingStats {
    function getGenderStats() external view returns (uint256 malePercent, uint256 femalePercent);
}

// NFT pour prouver vote / donation
contract VotingBadge is ERC721, Ownable {
    uint256 public nextTokenId;

    constructor() ERC721("VotingBadge", "VBADGE") Ownable(msg.sender) {}

    function mintBadge(address to) external onlyOwner returns (uint256) {
        nextTokenId++;
        _safeMint(to, nextTokenId);
        return nextTokenId;
    }
}

// Système de vote avec phases, dons, NFT et stats H/F
contract SimpleVotingSystem is Ownable, IVotingStats {


    struct Candidate {
        uint256 id;
        string name;
        uint256 voteCount;
    }

    enum Phase {
        None,
        Registration, 
        Donation,     
        Voting,       
        Counting      
    }

    enum Gender {
        Unknown,
        Male,
        Female
    }

  
    //error
    error WrongPhase(Phase expected, Phase current);
    error InvalidCandidateId();
    error AlreadyVoted();
    error TooEarlyForNextPhase(uint256 earliest, uint256 current);


    //event
    event PhaseAdminSet(uint8 indexed phase, address indexed admin);
    event PhaseStarted(Phase indexed phase, address indexed by);
    event PhaseEnded(Phase indexed phase, address indexed by);
    
    //event
    event CandidateAdded(uint256 indexed id, string name);
    event DonationReceived(address indexed from, uint256 amount);
    event VoteCast(address indexed voter, uint256 indexed candidateId, Gender gender);


    mapping(uint256 => Candidate) public candidates;
    uint256[] private candidateIds;

    mapping(address => bool) public voters;
    mapping(address => bool) public donors;

    VotingBadge public badge;

    Phase public currentPhase;
    uint256 public lastPhaseEnd; // date de fin de la dernière phase

    // les 4 admins de phase 
    address public phase1Admin;
    address public phase2Admin;
    address public phase3Admin;
    address public phase4Admin;

    mapping(address => Gender) public genderOfVoter;

    uint256 public maleCount;
    uint256 public femaleCount;
    uint256 public constant PHASE_DELAY = 1 hours;

    modifier onlyPhase(Phase expected) {
        if (currentPhase != expected) {
            revert WrongPhase(expected, currentPhase);
        }
        _;
    }

    modifier onlyPhaseAdminOrOwner(uint8 phaseNumber) {
        if (msg.sender == owner()) {
            _;
            return;
        }

        if (phaseNumber == 1 && msg.sender == phase1Admin) {
            _;
            return;
        }
        if (phaseNumber == 2 && msg.sender == phase2Admin) {
            _;
            return;
        }
        if (phaseNumber == 3 && msg.sender == phase3Admin) {
            _;
            return;
        }
        if (phaseNumber == 4 && msg.sender == phase4Admin) {
            _;
            return;
        }

        revert("Not phase admin");
    }

    constructor() Ownable(msg.sender) {
        // Le contrat de vote déploie son propre contrat de badge, dont il 
        // sera le owner 
        badge = new VotingBadge();
    }

    // ---------------------------------------------------------------------
    //                GESTION DES ADMINS DE PHASE
    // ---------------------------------------------------------------------

    // Definition de l'admin
    function setPhaseAdmin(uint8 phaseNumber, address admin) external onlyOwner {
        require(phaseNumber >= 1 && phaseNumber <= 4, "Invalid phase");
        if (phaseNumber == 1) {
            phase1Admin = admin;
        } else if (phaseNumber == 2) {
            phase2Admin = admin;
        } else if (phaseNumber == 3) {
            phase3Admin = admin;
        } else if (phaseNumber == 4) {
            phase4Admin = admin;
        }
        emit PhaseAdminSet(phaseNumber, admin);
    }

    // ---------------------------------------------------------------------
    //                GESTION DES PHASES
    // ---------------------------------------------------------------------

    //Démarre une phase Nous devons respecter l'ordre 1 -> 2 -> 3 -> 4 et le délai d'1h)
    function startPhase(uint8 phaseNumber) external onlyPhaseAdminOrOwner(phaseNumber) {
        require(phaseNumber >= 1 && phaseNumber <= 4, "Invalid phase");

        // on impose l'ordre : phase suivante = currentPhase + 1 sauf si 
        //aucune phase n'a encore eu lieu
        if (currentPhase == Phase.None) {
            require(phaseNumber == 1, "Must start with phase 1");
        } else {
            require(uint8(currentPhase) + 1 == phaseNumber, "Wrong phase order");
        }

        // Délai d'1h entre la fin de la phase précédente et le start de la suivante
        if (lastPhaseEnd != 0 && block.timestamp < lastPhaseEnd + PHASE_DELAY) {
            revert TooEarlyForNextPhase(lastPhaseEnd + PHASE_DELAY, block.timestamp);
        }

        currentPhase = Phase(phaseNumber);
        emit PhaseStarted(currentPhase, msg.sender);
    }

    // Termine la phase courante
    // Simplification : n'importe quel admin de phase OU le owner peut arrêter n'importe quelle phase
    function endCurrentPhase() external {
        require(currentPhase != Phase.None, "No active phase");

        bool isAdmin = (
            msg.sender == owner() ||
            msg.sender == phase1Admin ||
            msg.sender == phase2Admin ||
            msg.sender == phase3Admin ||
            msg.sender == phase4Admin
        );
        require(isAdmin, "Not allowed");

        Phase ended = currentPhase;
        currentPhase = Phase.None;
        lastPhaseEnd = block.timestamp;

        emit PhaseEnded(ended, msg.sender);
    }

    // ---------------------------------------------------------------------
    //                PHASE 1 : ENREGISTREMENT DES CANDIDATS
    // ---------------------------------------------------------------------

    function addCandidate(string memory _name)
        public
        onlyPhase(Phase.Registration)
    {
        require(bytes(_name).length > 0, "Candidate name cannot be empty");

        // Seul le super admin (owner) ou l'admin de phase 1
        require(
            msg.sender == owner() || msg.sender == phase1Admin,
            "Not allowed to add candidate"
        );

        uint256 candidateId = candidateIds.length + 1;
        candidates[candidateId] = Candidate(candidateId, _name, 0);
        candidateIds.push(candidateId);

        emit CandidateAdded(candidateId, _name);
    }

    // ---------------------------------------------------------------------
    //                PHASE 2 : DONATIONS (vers le super admin)
    // ---------------------------------------------------------------------

    function donate() public payable onlyPhase(Phase.Donation) {
        require(msg.value > 0, "No value sent");

        // On minte un badge uniquement lors du premier don
        if (!donors[msg.sender]) {
            donors[msg.sender] = true;
            badge.mintBadge(msg.sender);
        }
        payable(owner()).transfer(msg.value);

        emit DonationReceived(msg.sender, msg.value);
    }

    // ---------------------------------------------------------------------
    //                PHASE 3 : VOTE
    // ---------------------------------------------------------------------

    
    // Si isMale true = homme, false = femme (pour les stats)
    function vote(uint256 _candidateId, bool isMale)
        public
        onlyPhase(Phase.Voting)
    {
        if (voters[msg.sender]) revert AlreadyVoted();

        if (_candidateId == 0 || _candidateId > candidateIds.length) {
            revert InvalidCandidateId();
        }

        voters[msg.sender] = true;
        candidates[_candidateId].voteCount += 1;

        // Stats H/F
        Gender g = isMale ? Gender.Male : Gender.Female;
        genderOfVoter[msg.sender] = g;
        if (g == Gender.Male) {
            maleCount += 1;
        } else if (g == Gender.Female) {
            femaleCount += 1;
        }

        badge.mintBadge(msg.sender);

        emit VoteCast(msg.sender, _candidateId, g);
    }

    // ---------------------------------------------------------------------
    //                PHASE 4 : DÉPOUILLEMENT
    // ---------------------------------------------------------------------

    // Retourne le candidat gagnant
    function countVotes()
        public
        view
        onlyPhase(Phase.Counting)
        returns (uint256 winnerId, uint256 winnerVotes)
    {
        require(
            msg.sender == owner() || msg.sender == phase4Admin,
            "Not allowed to count"
        );

        uint256 maxVotes = 0;
        uint256 idGagnant = 0;

        for (uint256 i = 0; i < candidateIds.length; i++) {
            uint256 cid = candidateIds[i];
            uint256 votes = candidates[cid].voteCount;
            if (votes > maxVotes) {
                maxVotes = votes;
                idGagnant = cid;
            }
        }

        return (idGagnant, maxVotes);
    }

    // ---------------------------------------------------------------------
    //                LECTURE : CANDIDATS / VOTES / STATS
    // ---------------------------------------------------------------------

    function getTotalVotes(uint256 _candidateId) public view returns (uint256) {
        if (_candidateId == 0 || _candidateId > candidateIds.length) {
            revert InvalidCandidateId();
        }
        return candidates[_candidateId].voteCount;
    }

    function getCandidatesCount() public view returns (uint256) {
        return candidateIds.length;
    }

    function getCandidate(uint256 _candidateId)
        public
        view
        returns (Candidate memory)
    {
        if (_candidateId == 0 || _candidateId > candidateIds.length) {
            revert InvalidCandidateId();
        }
        return candidates[_candidateId];
    }

    // Pourcentage hommes / femmes (0–100).
    function getGenderStats()
        external
        view
        override
        returns (uint256 malePercent, uint256 femalePercent)
    {
        uint256 total = maleCount + femaleCount;
        if (total == 0) {
            return (0, 0);
        }

        malePercent = (maleCount * 100) / total;
        femalePercent = (femaleCount * 100) / total;
    }
}
