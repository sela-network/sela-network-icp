const axios = require('axios');

// Delay function that returns a promise
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Function to create a job
const createJob = async (index) => {
  const url = 'http://bkyz2-fmaaa-aaaaa-qaaaq-cai.localhost:4943/createJob';
  const headers = {
    'Authorization': `user${index}`,
    'Content-Type': 'application/json'
  };

  const body = {
    jobType: "performanceTest",
    target: `target${index}`
  };

  try {
    const response = await axios.post(url, body, { headers });
    console.log(`Job ${index} created:`, response.data);
    return response.data;
  } catch (error) {
    console.error(`Error creating job ${index}:`, error.message);
    return { status: 'error', error: error.message };
  }
};

// Function to mark job as complete
const jobComplete = async (userId) => {
  const url = 'http://bkyz2-fmaaa-aaaaa-qaaaq-cai.localhost:4943/updateJobCompleted';
  const headers = {
    'Authorization': `user${userId}`,
    'Content-Type': 'application/json'
  };

  const body = {
    client_id: userId,
    result: "success"
  };

  try {
    const response = await axios.post(url, body, { headers });
    console.log(`Job ${userId} completed:`, response.data);
    return response.data;
  } catch (error) {
    console.error(`Error completing job ${userId}:`, error.message);
    return { status: 'error', error: error.message };
  }
};

// Function to connect client
const connectClient = async (userId) => {
  const url = 'http://bkyz2-fmaaa-aaaaa-qaaaq-cai.localhost:4943/clientConnect';
  const headers = {
    'Authorization': `user${userId}`,
    'Content-Type': 'application/json'
  };

  const body = {
    client_id: userId
  };

  try {
    const response = await axios.post(url, body, { headers });
    console.log(`Client ${userId} connected:`, response.data);
    return response.data;
  } catch (error) {
    console.error(`Error connecting client ${userId}:`, error.message);
    return { status: 'error', error: error.message };
  }
};

// Function to perform all operations for a single user
const performOperationsForUser = async (index) => {
  try {
    const [job, client, completion] = await Promise.all([
      createJob(index),
      connectClient(index),
      jobComplete(index)
    ]);

    return { job, client, completion };
  } catch (error) {
    console.error(`Error performing operations for user ${index}:`, error.message);
    return { status: 'error', error: error.message };
  }
};

// Function to run the performance test
const runPerformanceTest = async (numOperations = 100) => {
  console.time('Total Test Duration');

  // Run operations in parallel for all users
  console.log('\nRunning performance test...');
  const operations = [];
  for (let i = 0; i < numOperations; i++) {
    operations.push(performOperationsForUser(i + 1));
  }

  // Wait for all operations to complete
  const results = await Promise.all(operations);

  console.timeEnd('Total Test Duration');

  // Print summary
  console.log('\nPerformance Test Summary:');
  console.log('-------------------------');
  console.log(`Total Users: ${numOperations}`);
  console.log(`Successful Jobs: ${results.filter(r => r.job?.status === "success").length}`);
  console.log(`Failed Jobs: ${results.filter(r => r.job?.status === "error").length}`);
  console.log(`Successful Connections: ${results.filter(r => r.client?.status === "success").length}`);
  console.log(`Failed Connections: ${results.filter(r => r.client?.status === "error").length}`);
  console.log(`Successful Completions: ${results.filter(r => r.completion?.status === "success").length}`);
  console.log(`Failed Completions: ${results.filter(r => r.completion?.status === "error").length}`);
};

// Run the test
runPerformanceTest()
  .then(() => console.log('Performance test completed'))
  .catch(error => console.error('Performance test failed:', error));
