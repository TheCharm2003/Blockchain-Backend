// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract GigEconomy {
    struct Worker {
        string name;
        string skill;
        uint completedTasks;
        address payable wallet;
        bool isRegistered;
        uint totalRatings;
        uint sumRatings;
    }

    struct Job {
        address client;
        address worker;
        string description;
        uint payment;
        bool isCompleted;
        bool isPaid;
        bool disputeRaised;
        bool workerRated;
        bool clientRated;
        address[] applicants;
    }

    struct Client {
        uint totalRatings;
        uint sumRatings;
    }

    mapping(address => Worker) public workers;
    mapping(uint => Job) public jobs;
    mapping(address => Client) public clients;

    address public owner;
    uint public jobCounter;

    event WorkerRegistered(address indexed worker, string name, string skill);
    event JobPosted(
        uint jobId,
        address indexed client,
        string description,
        uint payment
    );
    event JobApplied(uint jobId, address indexed applicant);
    event WorkerSelected(uint jobId, address indexed worker);
    event JobCompleted(uint jobId, address indexed worker);
    event PaymentReleased(uint jobId, address indexed worker, uint amount);
    event DisputeRaised(uint jobId, address indexed user);
    event DisputeResolved(uint jobId, string decision);
    event RatingGiven(
        address indexed target, // Renamed for clarity (can be worker or client)
        address indexed rater,
        uint8 rating
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only contract owner can call this");
        _;
    }

    modifier onlyRegistered() {
        require(workers[msg.sender].isRegistered, "Not a registered worker");
        _;
    }

    modifier jobExists(uint _jobId) {
        require(_jobId > 0 && _jobId < jobCounter, "Job does not exist");
        _;
    }

     modifier jobNotTaken(uint _jobId) {
        require(jobs[_jobId].worker == address(0), "Worker already selected for this job");
        _;
    }


    modifier jobNotDisputed(uint _jobId) {
        require(!jobs[_jobId].disputeRaised, "Dispute already raised");
        _;
    }

    constructor() {
        owner = msg.sender;
        jobCounter = 1;
    }

    function registerWorker(
        string calldata _name,
        string calldata _skill
    ) external {
        require(!workers[msg.sender].isRegistered, "Worker already registered");
        require(
            bytes(_name).length > 0 && bytes(_skill).length > 0,
            "Invalid name or skill"
        );
        workers[msg.sender] = Worker({
            name: _name,
            skill: _skill,
            completedTasks: 0,
            wallet: payable(msg.sender),
            isRegistered: true,
            totalRatings: 0,
            sumRatings: 0
        });
        emit WorkerRegistered(msg.sender, _name, _skill);
    }

    function postJob(
        string calldata _description,
        uint _payment
    ) external payable {
        require(
            bytes(_description).length > 0,
            "Job description cannot be empty"
        );
        require(msg.value == _payment, "Incorrect payment amount");
        require(_payment > 0, "Payment must be greater than 0");

        jobs[jobCounter] = Job({
            client: msg.sender,
            worker: address(0),
            description: _description,
            payment: _payment,
            isCompleted: false,
            isPaid: false,
            disputeRaised: false,
            workerRated: false,
            clientRated: false,
            applicants: new address[](0) 
        });
        emit JobPosted(jobCounter, msg.sender, _description, _payment);
        jobCounter++;
    }

    function applyForJob(
        uint _jobId
    ) external onlyRegistered jobExists(_jobId) jobNotTaken(_jobId) jobNotDisputed(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.client != msg.sender, "Client cannot apply for own job");
        for (uint i = 0; i < job.applicants.length; i++) {
            require(job.applicants[i] != msg.sender, "You have already applied for this job");
        }
        job.applicants.push(msg.sender);
        emit JobApplied(_jobId, msg.sender);
    }

    function selectWorker(uint _jobId, address _workerAddress) external jobExists(_jobId) jobNotDisputed(_jobId) jobNotTaken(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.client == msg.sender, "Only job client can select a worker");
        require(workers[_workerAddress].isRegistered, "Address is not a registered worker");

        bool isApplicant = false;
        for (uint i = 0; i < job.applicants.length; i++) {
            if (job.applicants[i] == _workerAddress) {
                isApplicant = true;
                break;
            }
        }
        require(isApplicant, "Worker has not applied for this job");
        job.worker = _workerAddress;
        emit WorkerSelected(_jobId, _workerAddress);
    }


    function completeJob(
        uint _jobId
    ) external onlyRegistered jobExists(_jobId) jobNotDisputed(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.worker == msg.sender, "You are not assigned to this job");
        require(!job.isCompleted, "Job already completed");
        job.isCompleted = true;
        workers[msg.sender].completedTasks++;
        emit JobCompleted(_jobId, msg.sender);
    }

    function releasePayment(
        uint _jobId
    ) external jobExists(_jobId) jobNotDisputed(_jobId) {
        Job storage job = jobs[_jobId];
        require(
            job.client == msg.sender,
            "Only job client can release payment"
        );
        require(job.isCompleted, "Job not completed yet");
        require(!job.isPaid, "Payment already released");
        require(job.worker != address(0), "No worker assigned yet");

        job.isPaid = true;
        uint paymentAmount = job.payment;
        (bool success, ) = job.worker.call{value: paymentAmount}("");
        require(success, "Payment transfer failed");
        emit PaymentReleased(_jobId, job.worker, paymentAmount);
    }

    function raiseDispute(
        uint _jobId
    ) external jobExists(_jobId) jobNotDisputed(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.worker != address(0), "No worker assigned yet");
        require(
            msg.sender == job.worker || msg.sender == job.client,
            "Unauthorized"
        );
        require(
            !job.isPaid,
            "Payment already released, dispute can't be raised"
        );
        job.disputeRaised = true;
        emit DisputeRaised(_jobId, msg.sender);
    }

    function resolveDispute(uint _jobId) external onlyOwner jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.disputeRaised, "No dispute raised for this job");
        require(!job.isPaid, "Payment already released");
        require(job.worker != address(0), "No worker assigned to resolve dispute for"); // Added check
        job.isPaid = true;
        Client storage client = clients[job.client];
        Worker storage worker = workers[job.worker];
        uint clientAverageRating = client.totalRatings > 0
            ? client.sumRatings / client.totalRatings
            : 3;
        uint workerAverageRating = worker.totalRatings > 0
            ? worker.sumRatings / worker.totalRatings
            : 3;
        if (workerAverageRating == clientAverageRating) {
            uint halfPayment = job.payment / 2;
            (bool successClient, ) = job.client.call{value: halfPayment}("");
            require(successClient, "Client refund transfer failed during dispute resolution");
            (bool successWorker, ) = job.worker.call{value: job.payment - halfPayment}("");
            require(successWorker, "Worker payment transfer failed during dispute resolution");
            emit DisputeResolved(
                _jobId,
                "Tie, funds split 50/50 between worker and client"
            );
        } else if (workerAverageRating > clientAverageRating) {
            (bool success, ) = job.worker.call{value: job.payment}("");
            require(success, "Worker payment transfer failed during dispute resolution");
            emit DisputeResolved(_jobId, "Worker wins, payment released");
        } else {
            (bool success, ) = job.client.call{value: job.payment}("");
            require(success, "Client refund transfer failed during dispute resolution");
            emit DisputeResolved(_jobId, "Client wins, funds returned");
        }
    }

    function rateClient(
        uint8 _rating,
        uint _jobId
    ) external onlyRegistered jobExists(_jobId) {
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");
        Job storage job = jobs[_jobId];
        require(job.worker == msg.sender, "Only worker assigned to job can rate client");
        require(job.isCompleted, "Job must be completed to rate client");
        require(job.clientRated == false, "Job client already rated.");
        Client storage client = clients[job.client];
        client.totalRatings++;
        client.sumRatings += _rating;
        job.clientRated = true;
        emit RatingGiven(job.client, msg.sender, _rating);
    }

    function getWorkerStats(
        address _worker
    ) external view returns (uint completedJobs, uint averageRating) {
        require(workers[_worker].isRegistered, "Worker not registered");
        Worker storage worker = workers[_worker];
        if (worker.totalRatings > 0) {
            return (
                worker.completedTasks,
                worker.sumRatings / worker.totalRatings
            );
        } else {
            return (worker.completedTasks, 0);
        }
    }

    function rateWorker(
        uint8 _rating,
        uint _jobId
    ) external jobExists(_jobId) {
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");
        Job storage job = jobs[_jobId];
        require(job.client == msg.sender, "Only client can rate worker");
        require(job.isCompleted, "Job must be completed to rate worker");
        require(job.worker != address(0), "No worker assigned to rate");
        require(job.workerRated == false, "Job worker already rated.");
        Worker storage worker = workers[job.worker];
        worker.totalRatings++;
        worker.sumRatings += _rating;
        job.workerRated = true;
        emit RatingGiven(job.worker, msg.sender, _rating);
    }

    function getJob(
        uint _jobId
    )
        external
        view
        jobExists(_jobId)
        returns (
            address client,
            address worker,
            string memory description,
            uint payment,
            bool isCompleted,
            bool isPaid,
            bool disputeRaised,
            bool workerRated,
            bool clientRated,
            address[] memory applicants
        )
    {
        Job storage job = jobs[_jobId];
        return (
            job.client,
            job.worker,
            job.description,
            job.payment,
            job.isCompleted,
            job.isPaid,
            job.disputeRaised,
            job.workerRated,
            job.clientRated,
            job.applicants
        );
    }

    receive() external payable {}
}