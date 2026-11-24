# checks.<system>.agent-cli: lib/agent.py up to the podman run it would exec:
# flags, the staged workspace, the clone and the remote, against a podman that
# only records.
{ hostPkgs }:
hostPkgs.runCommand "agent-cli-test" { nativeBuildInputs = [ hostPkgs.python3 hostPkgs.gitMinimal hostPkgs.jq ]; } ''
  cp ${../lib/agent.py} agent.py
  cp ${./agent_test.py} agent_test.py
  HOME=$PWD python3 -W error -m unittest -v agent_test
  touch $out
''
