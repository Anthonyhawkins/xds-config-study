// Import service-level common configuration
local serviceCommon = import "../common.jsonnet";

// Profile-specific overrides for us-west-2 cache deployment
serviceCommon + {
  "distribution": serviceCommon.regions + {
    // us-west-2 only for this cache deployment
    "us-west-2": serviceCommon.regions["us-west-2"] + {
      "priority": 0,
      "weight": 100
    }
  }
}