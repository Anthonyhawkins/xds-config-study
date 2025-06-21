{
  // Default configuration for TCP proxy role
  "load_balancing_method": "ROUND_ROBIN",
  "timeout": "30s",
  
  // Default regions configuration for TCP services
  "regions": {
    "us-east-1": {
      "priority": 0,
      "weight": 100
    },
    "us-west-2": {
      "priority": 1,
      "weight": 50
    },
    "eu-central": {
      "priority": 1,
      "weight": 50
    }
  }
}