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
        require(msg.sender == owner, "Only Owner Can Do This");
        _;
    }

    modifier onlyRegistered() {
        require(workers[msg.sender].isRegistered, "Not A Registered Worker");
        _;
    }

    modifier jobExists(uint _jobId) {
        require(_jobId > 0 && _jobId < jobCounter, "Job Does Not Exist");
        _;
    }

    modifier jobNotTaken(uint _jobId) {
        require(
            jobs[_jobId].worker == address(0),
            "Worker Already Selected"
        );
        _;
    }

    modifier jobNotDisputed(uint _jobId) {
        require(!jobs[_jobId].disputeRaised, "Dispute Already Raised");
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
        require(!workers[msg.sender].isRegistered, "Worker Already Registered");
        require(
            bytes(_name).length > 0 && bytes(_skill).length > 0,
            "Invalid Name or Skill"
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
            "Description cannot be empty"
        );
        require(msg.value == _payment, "Incorrect Amount");
        require(_payment > 0, "Payment Must Be Greater Than 0");

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
    )
        external
        onlyRegistered
        jobExists(_jobId)
        jobNotTaken(_jobId)
        jobNotDisputed(_jobId)
    {
        Job storage job = jobs[_jobId];
        require(job.client != msg.sender, "Cannot Apply For Own Job");
        for (uint i = 0; i < job.applicants.length; i++) {
            require(
                job.applicants[i] != msg.sender,
                "Already Applied"
            );
        }
        job.applicants.push(msg.sender);
        emit JobApplied(_jobId, msg.sender);
    }

    function selectWorker(
        uint _jobId,
        address _workerAddress
    ) external jobExists(_jobId) jobNotDisputed(_jobId) jobNotTaken(_jobId) {
        Job storage job = jobs[_jobId];
        require(
            job.client == msg.sender,
            "Only Client Can Select"
        );
        require(
            workers[_workerAddress].isRegistered,
            "Not A Registered Worker"
        );

        bool isApplicant = false;
        for (uint i = 0; i < job.applicants.length; i++) {
            if (job.applicants[i] == _workerAddress) {
                isApplicant = true;
                break;
            }
        }
        require(isApplicant, "Worker Has Not Applied");
        job.worker = _workerAddress;
        emit WorkerSelected(_jobId, _workerAddress);
    }

    function completeJob(
        uint _jobId
    ) external onlyRegistered jobExists(_jobId) jobNotDisputed(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.worker == msg.sender, "Job Not Assigned To You");
        require(!job.isCompleted, "Already Completed");
        job.isCompleted = true;
        workers[msg.sender].completedTasks++;
        emit JobCompleted(_jobId, msg.sender);
    }

    function releasePayment(
        uint _jobId
    ) external jobExists(_jobId) jobNotDisputed(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.isCompleted, "Job Not Completed");
        require(!job.isPaid, "Payment Already Released");
        require(
            job.client == msg.sender,
            "Only Client Can Release Payment"
        );
        require(job.worker != address(0), "No Worker Assigned");

        job.isPaid = true;
        uint paymentAmount = job.payment;
        (bool success, ) = job.worker.call{value: paymentAmount}("");
        require(success, "Payment Transfer Failed");
        emit PaymentReleased(_jobId, job.worker, paymentAmount);
    }

    function raiseDispute(
        uint _jobId
    ) external jobExists(_jobId) jobNotDisputed(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.worker != address(0), "No Worker Assigned");
        require(
            msg.sender == job.worker || msg.sender == job.client,
            "Unauthorized"
        );
        require(
            !job.isPaid,
            "Payment Already Released, Dispute Can't Be Raised"
        );
        job.disputeRaised = true;
        emit DisputeRaised(_jobId, msg.sender);
    }

    function resolveDispute(uint _jobId) external onlyOwner jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.disputeRaised, "No Dispute For The Job");
        require(!job.isPaid, "Payment Already Released");
        require(
            job.worker != address(0),
            "No Worker Assigned"
        );
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
            require(
                successClient,
                "Transfer Failed"
            );
            (bool successWorker, ) = job.worker.call{
                value: job.payment - halfPayment
            }("");
            require(
                successWorker,
                "Transfer Failed"
            );
            emit DisputeResolved(
                _jobId,
                "Dispute Resolved"
            );
        } else if (workerAverageRating > clientAverageRating) {
            (bool success, ) = job.worker.call{value: job.payment}("");
            require(
                success,
                "Transfer Failed"
            );
            emit DisputeResolved(_jobId, "Dispute Resolved");
        } else {
            (bool success, ) = job.client.call{value: job.payment}("");
            require(
                success,
                "Transfer Failed"
            );
            emit DisputeResolved(_jobId, "Dispute Resolved");
        }
    }

    function rateClient(
        uint8 _rating,
        uint _jobId
    ) external onlyRegistered jobExists(_jobId) {
        require(_rating >= 1 && _rating <= 5, "Rating Must Be Between 1 and 5");
        Job storage job = jobs[_jobId];
        require(
            job.worker == msg.sender,
            "Only Assigned Worker Can Rate"
        );
        require(job.isCompleted, "Job Not Completed");
        require(job.clientRated == false, "Client Already Rated.");
        Client storage client = clients[job.client];
        client.totalRatings++;
        client.sumRatings += _rating;
        job.clientRated = true;
        emit RatingGiven(job.client, msg.sender, _rating);
    }

    function getWorkerStats(
        address _worker
    ) external view returns (uint completedJobs, uint averageRating) {
        require(workers[_worker].isRegistered, "Worker Not Registered");
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

    function getClientStats(
        address _client
    ) external view returns (uint averageRating) {
        Client storage client = clients[_client];

        if (client.totalRatings > 0) {
            return (
                client.sumRatings / client.totalRatings
            );
        } else {
            return (0);
        }
    }

    function rateWorker(uint8 _rating, uint _jobId) external jobExists(_jobId) {
        require(_rating >= 1 && _rating <= 5, "Rating Must Be Between 1 and 5");
        Job storage job = jobs[_jobId];
        require(job.client == msg.sender, "Only Client Can Rate");
        require(job.isCompleted, "Job Not Completed");
        require(job.worker != address(0), "No Worker Assigned");
        require(job.workerRated == false, "Worker Already Rated.");
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
            address[] memory applicants,
            string memory workerName
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
            job.applicants,
            job.worker != address(0) ? workers[job.worker].name : ""
        );
    }

    receive() external payable {}
}
