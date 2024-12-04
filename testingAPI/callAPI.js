const axios = require('axios');

// Function to make a POST request with a dynamic Authorization header
const makeRequest = async (userId) => {
  const url = 'http://b77ix-eeaaa-aaaaa-qaada-cai.localhost:4943/clientAlive';
  const headers = {
    'Authorization': `user${userId}`, // Dynamic Authorization header
  };

  try {
    const response = await axios.post(url, {}, { headers });
    console.log(`Response for user${userId}:`, response.data);
  } catch (error) {
    console.error(`Error for user${userId}:`, error.message);
  }
};

// Function to call the API for 20 users concurrently every 5 seconds
const callApiEvery5Seconds = () => {
  setInterval(() => {
    const userRequests = [];

    // Generate 20 user requests and call the API concurrently
    for (let i = 1; i <= 20; i++) {
      userRequests.push(makeRequest(i));
    }

    // Wait for all requests to complete
    Promise.all(userRequests)
      .then(() => {
        console.log('All API calls completed for this interval.');
      })
      .catch((error) => {
        console.error('Error in some API calls:', error);
      });
  }, 5000); // 5000ms = 5 seconds
};

// Start the periodic API calls
callApiEvery5Seconds();
