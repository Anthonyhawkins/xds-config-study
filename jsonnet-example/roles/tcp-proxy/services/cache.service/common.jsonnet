// Import role-level common configuration
local roleCommon = import "../../common.jsonnet";

// Service-specific overrides for cache service
roleCommon + {
  // Cache connections are fast
  "timeout": "2s",
  
  // Cache-specific regions - single region deployment only
  "regions": {
    "us-west-2": {
      "priority": 0,
      "weight": 100
    }
  }
}