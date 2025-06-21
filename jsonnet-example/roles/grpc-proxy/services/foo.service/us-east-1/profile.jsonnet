// Import service-level common configuration (which includes role-level)
local serviceCommon = import "../common.jsonnet";

// Profile-specific overrides for us-east-1 region
serviceCommon + {
  // Use the common configuration but override distribution for this specific profile
  "distribution": serviceCommon.regions + {
    // Override eu-central to be primary for this specific profile
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 0,
      "weight": 100
    },
    // us-east-1 and us-west-2 become failover with different priorities
    "us-east-1": serviceCommon.regions["us-east-1"] + {
      "priority": 1,
      "weight": 60
    },
    "us-west-2": serviceCommon.regions["us-west-2"] + {
      "priority": 1,
      "weight": 40
    }
  }
}