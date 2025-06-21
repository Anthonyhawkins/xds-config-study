// Import role-level common configuration
local roleCommon = import "../../common.jsonnet";

// Service-specific overrides for web service
roleCommon + {
  // Web services can use longer timeouts
  "timeout": "15s",
  
  // Different load balancing for web traffic
  "load_balancing_method": "ROUND_ROBIN",
  
  // Web-specific regions - balance between US West and EU only
  "regions": {
    "us-west-2": {
      "priority": 0,
      "weight": 50
    },
    "eu-central": {
      "priority": 0,
      "weight": 50
    }
  }
}