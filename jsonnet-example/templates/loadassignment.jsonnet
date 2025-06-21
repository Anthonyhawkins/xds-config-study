// Import region/IP/port config from a separate file
local gateways = import "endpoints.jsonnet";
local profile = import "profile.jsonnet";

{
  resources: [
    {
      // account for role and region in resource name
      cluster_name: std.extVar("role") + "." + std.extVar("region") + "." + std.extVar("cluster_name"),
      endpoints: [
        {
          locality: {
            region: region,
          },
          priority: profile["distribution"][region]["priority"],
          load_balancing_weight: profile["distribution"][region]["weight"],
          lb_endpoints: [
            {
              endpoint: {
                address: {
                  socket_address: {
                    address: ip,
                    port_value: gateways["gateways"][region].port,
                  }
                }
              }
            }
            for ip in gateways["gateways"][region].ips
          ]
        }
        for region in std.objectFields(profile["distribution"])
      ]
    }
  ]
}
