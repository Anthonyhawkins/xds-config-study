// Import role-level common configuration
local roleCommon = import "../../common.jsonnet";

// Service-specific overrides for database service
roleCommon + {
  // Database connections need longer timeouts
  "timeout": "60s",
  
  // Database-specific regions - prefer primary/secondary pattern
  "regions": roleCommon.regions + {
    "us-east-1": roleCommon.regions["us-east-1"] + {
      "priority": 0,
      "weight": 100
    },
    "eu-central": roleCommon.regions["eu-central"] + {
      "priority": 1,
      "weight": 100
    },
    // Remove us-west-2 from db.service distribution
    "us-west-2": roleCommon.regions["us-west-2"] + {
      "priority": 2,
      "weight": 100
    }
  }
}