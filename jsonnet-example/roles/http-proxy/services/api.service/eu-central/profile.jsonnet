// Import service-level common configuration
local serviceCommon = import "../common.jsonnet";

// Profile-specific overrides for eu-central API deployment
serviceCommon + {
  "distribution": serviceCommon.regions + {
    // eu-central is primary for this API deployment
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 0,
      "weight": 100
    },
    // US regions as failover
    "us-east-1": serviceCommon.regions["us-east-1"] + {
      "priority": 1,
      "weight": 70
    },
    "us-west-2": serviceCommon.regions["us-west-2"] + {
      "priority": 1,
      "weight": 30
    }
  }
}