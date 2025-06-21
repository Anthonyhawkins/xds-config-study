local profile = import "profile.jsonnet";

{
  "name": std.extVar("cluster_name"),
  "connect_timeout": profile["timeout"],
  "load_assignment": {
    "cluster_name": std.extVar("cluster_name"),
  }
}