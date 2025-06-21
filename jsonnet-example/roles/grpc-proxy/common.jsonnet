{
  // Default configuration for gRPC proxy role
  "load_balancing_method": "ROUND_ROBIN",
  "timeout": "5s",
  
  // Default regions configuration
  "regions": {
    "us-east-1": {
      "priority": 0,
      "weight": 100
    },
    "us-west-2": {
      "priority": 1,
      "weight": 100
    },
    "eu-central": {
      "priority": 2,
      "weight": 100
    }
  }
}