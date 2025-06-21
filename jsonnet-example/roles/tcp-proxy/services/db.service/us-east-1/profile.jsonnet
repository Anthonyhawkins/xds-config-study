// Import service-level common configuration
local serviceCommon = import "../common.jsonnet";

// Profile-specific overrides for us-east-1 database deployment
serviceCommon + {
  "distribution": serviceCommon.regions + {
    // us-east-1 is primary database
    "us-east-1": serviceCommon.regions["us-east-1"] + {
      "priority": 0,
      "weight": 100
    },
    // eu-central as standby
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 1,
      "weight": 100
    }
  }
}