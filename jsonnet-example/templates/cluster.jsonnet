local profile = import "profile.jsonnet";

{
  // acount for role and region in name and cluster name
  "name": std.extVar("role") + "." + std.extVar("region") + "." + std.extVar("cluster_name"),
  "connect_timeout": profile["timeout"],
  "load_assignment": {
    "cluster_name": std.extVar("role") + "." + std.extVar("region") + "." + std.extVar("cluster_name"),
  }
}