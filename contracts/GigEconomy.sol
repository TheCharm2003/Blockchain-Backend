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
        bool cilentRated;
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
    event JobAccepted(uint jobId, address indexed worker);
    event JobCompleted(uint jobId, address indexed worker);
    event PaymentReleased(uint jobId, address indexed worker, uint amount);
    event DisputeRaised(uint jobId, address indexed user);
    event DisputeResolved(uint jobId, string decision);
    event RatingGiven(
        address indexed worker,
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
        require(_jobId > 0 && _jobId <= jobCounter, "Job does not exist");
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

        jobs[jobCounter] = Job({
            client: msg.sender,
            worker: address(0),
            description: _description,
            payment: _payment,
            isCompleted: false,
            isPaid: false,
            disputeRaised: false,
            workerRated: false,
            cilentRated: false
        });
        emit JobPosted(jobCounter, msg.sender, _description, _payment);
        jobCounter++;
    }

    function acceptJob(
        uint _jobId
    ) external onlyRegistered jobExists(_jobId) jobNotDisputed(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.worker == address(0), "Job already taken");
        require(!job.isCompleted, "Job already completed");
        for (uint i = 1; i < jobCounter; i++) {
            if (jobs[i].worker == msg.sender && !jobs[i].isCompleted) {
                revert(
                    "You must complete your current job before accepting a new one"
                );
            }
        }
        job.worker = msg.sender;
        emit JobAccepted(_jobId, msg.sender);
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
            require(successClient, "Client refund transfer failed");

            (bool successWorker, ) = job.worker.call{value: halfPayment}("");
            require(successWorker, "Worker payment transfer failed");

            emit DisputeResolved(
                _jobId,
                "Tie, funds split 50/50 between worker and client"
            );
        } else if (workerAverageRating > clientAverageRating) {
            (bool success, ) = job.worker.call{value: job.payment}("");
            require(success, "Worker payment transfer failed");
            emit DisputeResolved(_jobId, "Worker wins, payment released");
        } else {
            (bool success, ) = job.client.call{value: job.payment}("");
            require(success, "Client refund transfer failed");
            emit DisputeResolved(_jobId, "Client wins, funds returned");
        }
    }

    function rateClient(
        uint8 _rating,
        uint _jobId
    ) external onlyRegistered jobExists(_jobId) {
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");
        Job storage job = jobs[_jobId];
        require(job.worker == msg.sender, "Only worker can rate client");
        require(job.isCompleted, "Job must be completed");
        Client storage client = clients[job.client];
        require(job.cilentRated == false, "Job Client already rated.");
        client.totalRatings++;
        client.sumRatings += _rating;
        emit RatingGiven(job.worker, job.client, _rating);
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
        require(job.isCompleted, "Job must be completed");
        require(job.workerRated == false, "Job Worker already rated.");
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
            bool cilentRated
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
            job.cilentRated
        );
    }

    receive() external payable {}
}