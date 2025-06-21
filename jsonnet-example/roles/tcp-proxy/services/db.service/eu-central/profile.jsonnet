// Import service-level common configuration
local serviceCommon = import "../common.jsonnet";

// Profile-specific overrides for eu-central database deployment
serviceCommon + {
  "distribution": serviceCommon.regions + {
    // eu-central is primary database for EU
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 0,
      "weight": 100
    },
    // us-east-1 as standby
    "us-east-1": serviceCommon.regions["us-east-1"] + {
      "priority": 1,
      "weight": 100
    }
  }
}