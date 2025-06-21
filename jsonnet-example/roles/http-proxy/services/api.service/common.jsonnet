// Import role-level common configuration
local roleCommon = import "../../common.jsonnet";

// Service-specific overrides for API service
roleCommon + {
  // API services need faster timeouts
  "timeout": "5s",
  
  // API-specific regions - prioritize US regions
  "regions": roleCommon.regions + {
    "us-east-1": roleCommon.regions["us-east-1"] + {
      "priority": 0,
      "weight": 70
    },
    "us-west-2": roleCommon.regions["us-west-2"] + {
      "priority": 0,
      "weight": 30
    },
    "eu-central": roleCommon.regions["eu-central"] + {
      "priority": 1,
      "weight": 100
    }
  }
}