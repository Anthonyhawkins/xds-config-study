// Import service-level common configuration
local serviceCommon = import "../common.jsonnet";

// Profile-specific overrides for us-west-2 web deployment
serviceCommon + {
  "distribution": serviceCommon.regions + {
    // us-west-2 is primary for this web deployment
    "us-west-2": serviceCommon.regions["us-west-2"] + {
      "priority": 0,
      "weight": 100
    },
    // eu-central as failover
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 1,
      "weight": 100
    }
  }
}