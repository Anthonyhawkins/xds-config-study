// Import service-level common configuration
local serviceCommon = import "../common.jsonnet";

// Profile-specific overrides for us-east-1 API deployment
serviceCommon + {
  "distribution": serviceCommon.regions + {
    // us-east-1 is primary for this API deployment
    "us-east-1": serviceCommon.regions["us-east-1"] + {
      "priority": 0,
      "weight": 100
    },
    // Other regions as failover
    "us-west-2": serviceCommon.regions["us-west-2"] + {
      "priority": 1,
      "weight": 60
    },
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 1,
      "weight": 40
    }
  }
}