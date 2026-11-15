# What gensokyo-agent --closure puts in a sandbox: packages, on the agent's PATH
# before the sandbox's own, and MCP servers for claude. A project exports
# one per name, and the owner picks it with --closure FLAKE#NAME (#default when
# no name is given):
#
#   agentClosures.${system}.default = nornpkgs.lib.mkAgentClosure {
#     inherit pkgs;
#     packages = [ pkgs.lean4 ];
#     mcpServers.lean = {
#       command = "${lean-lsp-mcp}/bin/lean-lsp-mcp";
#       # a server starts in the workspace, and claude fills in the ${VAR}s
#       # of its own environment: this is the checkout of my-project
#       env.LEAN_PROJECT_PATH = "\${PWD}/src/my-project";
#     };
#   };
#
# A server is in the format of a .mcp.json entry. The sandbox has no other
# copy of it: name its command by store path, or put its package in packages.
pkgs: { name ? "agent-closure", packages ? [ ], mcpServers ? { } }:
pkgs.buildEnv {
  inherit name;
  paths = packages ++ [
    # the store paths in the servers' commands come along: toJSON keeps them
    (pkgs.writeTextDir "share/gensokyo-agent/mcp.json" (builtins.toJSON { inherit mcpServers; }))
  ];
  passthru = { inherit mcpServers; };
}
