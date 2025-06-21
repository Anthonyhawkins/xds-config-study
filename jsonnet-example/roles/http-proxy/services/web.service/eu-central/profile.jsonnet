// Import service-level common configuration
local serviceCommon = import "../common.jsonnet";

// Profile-specific overrides for eu-central web deployment
serviceCommon + {
  "distribution": serviceCommon.regions + {
    // eu-central is primary for this web deployment
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 0,
      "weight": 100
    },
    // us-west-2 as failover
    "us-west-2": serviceCommon.regions["us-west-2"] + {
      "priority": 1,
      "weight": 100
    }
  }
}