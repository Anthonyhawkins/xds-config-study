// Import role-level common configuration
local roleCommon = import "../../common.jsonnet";

// Service-specific overrides and additions
roleCommon + {
  // bar.service uses different load balancing
  "load_balancing_method": "LEAST_REQUEST",
  
  // Different timeout for bar.service (slower processing expected)
  "timeout": "8s",
  
  // Service-specific regions configuration
  "regions": roleCommon.regions + {
    "us-east-1": roleCommon.regions["us-east-1"] + {
      "priority": 0,
      "weight": 80
    },
    "us-west-2": roleCommon.regions["us-west-2"] + {
      "priority": 0,
      "weight": 20
    },
    "eu-central": roleCommon.regions["eu-central"] + {
      "priority": 1,
      "weight": 100
    }
  }
}