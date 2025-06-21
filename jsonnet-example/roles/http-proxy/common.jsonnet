{
  // Default configuration for HTTP proxy role
  "load_balancing_method": "LEAST_REQUEST",
  "timeout": "10s",
  
  // Default regions configuration for HTTP services
  "regions": {
    "us-east-1": {
      "priority": 0,
      "weight": 60
    },
    "us-west-2": {
      "priority": 0,
      "weight": 40
    },
    "eu-central": {
      "priority": 1,
      "weight": 100
    }
  }
}