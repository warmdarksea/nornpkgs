import contextlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest import mock

import agent

# a podman that knows a few containers on this host and one on library, the
# token secret, and keeps what it was given
STUB = """#!{python}
import json, os, shutil, sys, tarfile
args = sys.argv[1:]
out = os.environ["STUB_OUT"]
with open(os.path.join(out, os.path.basename(sys.argv[0])), "a") as f:
    f.write(json.dumps(args) + "\\n")
conn = args[1] if args[:1] == ["-c"] else None
if "connection" in args:
    print(json.dumps([{{"Name": "library", "URI": "ssh://alice@library.example:2222/run/user/1000/podman/podman.sock", "Identity": "/id"}},
                      {{"Name": "pipe", "URI": "unix:///run/podman.sock"}}]))
def label(closure):
    return json.dumps({{"closure": closure, "servers": ["lean"], "opts": {{}}}})
# old: made before the label, carried on from one at .../older, with a volume; rec: one with
# the label and a closure, running; lib: rec's kind on library; bare: no workspace
ws = os.environ.get("STUB_WS", "/var/tmp/gensokyo-agent")
found = {{
    None: {{
        "old": {{"Config": {{"Labels": {{"gensokyo-agent": "old"}}, "WorkingDir": ws + "/older"}},
                "Mounts": [{{"Destination": "/.gensokyo-agent/closure", "Source": "/etc/gensokyo-agent/closure"}},
                           {{"Destination": ws + "/older/data", "Source": "/vol"}}]}},
        "rec": {{"Config": {{"Labels": {{"gensokyo-agent": "rec", "gensokyo-agent.opts": label(os.environ.get("STUB_REC_CLOSURE"))}},
                           "WorkingDir": ws + "/rec"}}, "State": {{"Running": True}}, "Image": "0ld1mage",
                "Mounts": [{{"Destination": ws + "/rec/data", "Source": "/vol"}}]}},
        "bare": {{"Config": {{"Labels": None, "WorkingDir": "/"}}}},
    }},
    "library": {{
        "lib": {{"Config": {{"Labels": {{"gensokyo-agent": "lib", "gensokyo-agent.opts": label(os.environ.get("STUB_REC_CLOSURE"))}},
                           "WorkingDir": ws + "/lib"}}, "State": {{"Running": False}}, "Image": "l1b"}},
    }},
}}
# pipe is this host again
found = found[None] if conn in (None, "pipe") else found.get(conn, {{}})
if "ps" in args:
    print(json.dumps([{{"Id": "id-" + n, "Names": [n]}} for n, c in found.items() if (c["Config"]["Labels"] or {{}}).get("gensokyo-agent")]))
if "exists" in args:
    sys.exit(0 if args[-1] in ("claude-oauth-token", *os.environ.get("STUB_SECRETS", "").split(), *found) else 1)
if "inspect" in args:
    if args[-1] not in found:
        sys.exit(125)
    print(json.dumps([found[args[-1]]]))
if "cp" in args:
    src = os.environ["STUB_FROM"] if args[-2].endswith("/.claude") else os.environ.get("STUB_WORK")
    if args[-2].endswith("/.claude/projects"):
        src = os.environ.get("STUB_PROJECTS", "").replace("NAME", args[-2].split(":")[0])
        if not os.path.isdir(src):
            sys.exit(125)
    if args[-1] == "-":
        with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as tar:
            tar.add(src, "projects")
        sys.exit(0)
    if src:
        shutil.copytree(src, args[-1], symlinks=True)
    else:
        os.mkdir(args[-1])
if "build" in args:
    shutil.rmtree(os.path.join(out, "ctx"), ignore_errors=True)
    shutil.copytree(args[-1], os.path.join(out, "ctx"), symlinks=True)
    shutil.move(os.path.join(out, "ctx", "Containerfile"), os.path.join(out, "Containerfile"))
"""

# a nix whose build links the out-link to the store path it is given, or to
# $STUB_CLOSURE for a flake; and whose copy copies nothing
NIX = """#!{python}
import json, os, sys
args = sys.argv[1:]
with open(os.path.join(os.environ["STUB_OUT"], "nix"), "a") as f:
    f.write(json.dumps(args) + "\\n")
with open(os.path.join(os.environ["STUB_OUT"], "nixenv"), "a") as f:
    f.write(json.dumps(os.environ.get("NIX_SSHOPTS")) + "\\n")
if "copy" in args:
    sys.exit(0)
built = args[-1] if "#" not in args[-1] else os.environ["STUB_CLOSURE"]
if not os.path.isdir(built):
    sys.exit(1)
link = args[args.index("--out-link") + 1]
if os.path.lexists(link):
    os.remove(link)
os.symlink(built, link)
"""
MCP = "--mcp-config /.gensokyo-agent/closure/share/gensokyo-agent/mcp.json"


@contextlib.contextmanager
def quiet():
    with open(os.devnull, "w") as null, contextlib.redirect_stderr(null):
        yield


def git(cwd, *args):
    return subprocess.run(["git", "-C", cwd, *args], check=True, stdout=subprocess.PIPE, text=True).stdout.strip()


class AgentTest(unittest.TestCase):
    def setUp(self):
        self.tmp = self.enterContext(tempfile.TemporaryDirectory())
        self.out = os.path.join(self.tmp, "out")
        os.mkdir(self.out)
        podman = os.path.join(self.tmp, "podman")
        with open(podman, "w") as f:
            f.write(STUB.format(python=sys.executable))
        os.chmod(podman, 0o755)
        ssh = os.path.join(self.tmp, "ssh")
        shutil.copy(podman, ssh)
        nix = os.path.join(self.tmp, "nix")
        with open(nix, "w") as f:
            f.write(NIX.format(python=sys.executable))
        os.chmod(nix, 0o755)
        root = os.path.join(self.tmp, "rootfs")
        os.makedirs(os.path.join(root, "home", "agent"))
        self.conf = {
            "podman": podman,
            "git": "git",
            "ssh": ssh,
            "nix": nix,
            "system": "x86_64-linux",
            "closure": {"at": "/.gensokyo-agent/closure", "default": "/etc/gensokyo-agent/closure"},
            "defaultCmd": "claude --dangerously-skip-permissions",
            "token": {"secret": "claude-oauth-token", "target": "CLAUDE_CODE_OAUTH_TOKEN"},
            # as lib/agent.nix has them
            "agents": {
                "claude": {"flags": {"model": ["--model", "%s"], "effort": ["--effort", "%s"]}},
                "agy": {
                    "flags": {"model": ["--model", "%s"], "effort": ["--effort", "%s"]},
                    "tokens": [
                        {"secret": "agy-oauth-token", "file": ".gemini/antigravity-cli/antigravity-oauth-token"},
                        {"secret": "gemini-api-key", "target": "GEMINI_API_KEY",
                         "home": {".gemini/antigravity-cli/settings.json": {"modelProvider": "gemini"}}},
                    ],
                    "missing": "agy starts logged out",
                    "mcp": {"path": ".gemini/config/mcp_config.json", "format": "agy"},
                    "home": {".gemini/antigravity-cli/settings.json": {"colorScheme": "solarized light"}},
                    "args": ["--add-host", "play.googleapis.com:127.0.0.1"],
                    "instructions": "AGENTS.md",
                },
                "codex": {
                    "flags": {"model": ["-m", "%s"], "effort": ["-c", "model_reasoning_effort=%s"]},
                    "mcp": {"path": ".codex/config.toml", "format": "codex"},
                    "home": {".codex/config.toml": '[tui]\ntheme = "solarized-light"\n\n'},
                    "instructions": "AGENTS.md",
                },
            },
            "hereArgs": ["--rm"],
            "root": root, "user": "4738:384", "home": "/home/agent",
            "runArgs": ["--init"], "gpuArgs": ["--device", "/dev/gpu"], "vmArgs": ["--device", "/dev/kvm"],
        }
        self.base = os.path.join(self.tmp, "ws")
        self.enterContext(mock.patch.dict(os.environ, {
            "STUB_OUT": self.out, "GENSOKYO_AGENT_TMPDIR": self.base, "STUB_WS": self.base,
            "GIT_AUTHOR_NAME": "o", "GIT_AUTHOR_EMAIL": "o@o",
            "GIT_COMMITTER_NAME": "o", "GIT_COMMITTER_EMAIL": "o@o",
        }))
        os.environ.pop("AGENT_CMD", None)
        os.environ.pop("GENSOKYO_AGENT_PODMAN", None)

    def repo(self):
        top = os.path.join(self.tmp, "proj")
        git(self.tmp, "init", "-q", "-b", "master", top)
        for i in "123":
            with open(os.path.join(top, "f"), "w") as f:
                f.write(i)
            git(top, "add", "f")
            git(top, "commit", "-q", "-m", f"c{i}")
        git(top, "tag", "v1")
        return top

    def new(self, *argv):
        """A workspace up to the podman run it would exec; returns that argv."""
        opts, cmd, passthrough = agent.parse_args(list(argv))
        with mock.patch("os.execvp") as execvp, quiet():
            agent.new_workspace(self.conf, opts, cmd, passthrough)
        return execvp.call_args[0][1]

    def dies(self, *argv):
        with self.assertRaises(SystemExit), quiet():
            self.new(*argv)

    def test_legacy_takes_the_rest_as_the_command(self):
        self.assertEqual(agent.parse_args(["--legacy", "codex", "--foo"]), (None, ["codex", "--foo"], []))
        self.assertEqual(agent.parse_args(["--legacy"]), (None, [], []))
        self.assertEqual(agent.parse_args([])[1:], ([], []))
        with self.assertRaises(SystemExit), quiet():
            agent.parse_args(["codex"])

    def test_flags_command_and_passthrough(self):
        opts, cmd, passthrough = agent.parse_args(
            ["--memory", "4g", "-c", "library", "-s", "k,type=env", "--", "codex", "--legacy"])
        self.assertEqual((opts.connection, opts.secret), ("library", ["k,type=env"]))
        self.assertEqual(cmd, ["codex", "--legacy"])
        self.assertEqual(passthrough, ["--memory", "4g"])

    def test_item_specs(self):
        src = os.path.join(self.tmp, "Some Data")
        os.mkdir(src)
        self.assertEqual(agent.parse_item("--ro", f"{src}:data/Some Set:the set: all of it"),
                         ("data-Some-Set", src, "data/Some Set", "the set: all of it"))
        self.assertEqual(agent.parse_item("--rw", f"shared={src}:scratch")[0], "shared")
        self.assertEqual(agent.parse_item("--cp", f"{src}:a/../b")[2], "b")
        for bad in (f"{src}:/abs", f"{src}:../up", f"{src}", f"{src}/missing:x"):
            with self.assertRaises(SystemExit), quiet():
                agent.parse_item("--cp", bad)

    def test_model_and_effort_reach_claude_as_given(self):
        self.new("--name", "ws7", "--model", "some-new-model[1m]", "--effort", "xhigh", "--prompt", "go")
        with open(os.path.join(self.out, "ctx", "root", ".gensokyo-agent", "entrypoint")) as f:
            entry = f.read()
        self.assertIn(f"--model 'some-new-model[1m]' --effort xhigh {MCP} -- go\n", entry)
        self.assertIn(f"--model 'some-new-model[1m]' --effort xhigh {MCP} --continue && exit\n", entry)
        self.new("--name", "ws8")
        with open(os.path.join(self.out, "ctx", "root", ".gensokyo-agent", "entrypoint")) as f:
            self.assertNotIn("--model", f.read())
        # that of the settings then
        with open(os.path.join(self.out, "ctx", "home", ".claude", "settings.json")) as f:
            self.assertEqual(json.load(f)["model"], "claude-opus-5-5[1m]")
        # each agent's own way, and none for one the wrapper does not know
        self.new("--name", "ws15", "--model", "gpt-9", "--effort", "high", "--", "codex", "--x")
        self.assertIn("exec codex --x -m gpt-9 -c model_reasoning_effort=high\n", self.staged("root", ".gensokyo-agent", "entrypoint"))
        self.new("--name", "ws16", "--model", "gemini-9-pro", "--effort", "max", "--", "agy")
        self.assertIn("exec agy --model gemini-9-pro --effort max\n", self.staged("root", ".gensokyo-agent", "entrypoint"))
        self.dies("--model", "opus", "--", "opencode")
        self.dies("--effort", "high", "--", "opencode")

    def test_entrypoint_resumes_claude_only(self):
        claude = agent.entrypoint(["claude", "--x"], "it's time")
        self.assertIn('claude --x --continue && exit', claude)
        # a list flag of claude's would take the prompt for one more of its words
        self.assertIn("exec claude --x -- 'it'\"'\"'s time'", claude)
        self.assertNotIn("--continue", agent.entrypoint(["codex"], None))
        self.assertIn("exec codex go\n", agent.entrypoint(["codex"], "go"))
        self.assertIn("exec claude --continue -- go\n", agent.entrypoint(["claude"], "go", resume=True))
        self.assertIn("exec codex go\n", agent.entrypoint(["codex"], "go", resume=True))

    def test_workspace(self):
        data = os.path.join(self.tmp, "data")
        os.mkdir(data)
        with open(os.path.join(data, "a"), "w") as f:
            f.write("a")
        run = self.new("--name", "ws1", "--cp", f"{data}/a:notes/a:a note", "--ro", f"{data}:sets/d",
                       "--rw", f"old={data}:scratch", "--bind", f"{data}:live", "--gpu",
                       "-s", "k,type=env", "--prompt", "go", "--memory", "4g")
        work = os.path.join(self.base, "ws1")
        ctx = os.path.join(self.out, "ctx")
        with open(os.path.join(self.out, "Containerfile")) as f:
            self.assertEqual(f.read(), "FROM scratch\nCOPY root/ /\n"
                             f"COPY --chown=4738:384 home/ /home/agent/\nCOPY --chown=4738:384 work/ {work}/\n")
        self.assertTrue(os.path.isfile(os.path.join(ctx, "work", "notes", "a")))
        self.assertTrue(os.path.isfile(os.path.join(ctx, "work", "sets", "d", "a")))
        # the volume that exists is not seeded again
        self.assertEqual(os.listdir(os.path.join(ctx, "work", "scratch")), [])
        self.assertFalse(os.path.exists(os.path.join(ctx, "work", "live")))
        # the agent's home is made by the chown'ed COPY, not by the skeleton
        self.assertFalse(os.path.exists(os.path.join(ctx, "root", "home", "agent")))
        with open(os.path.join(ctx, "home", ".claude.json")) as f:
            state = json.load(f)
        self.assertTrue(state["projects"][work]["hasTrustDialogAccepted"])
        self.assertTrue(state["hasSeenAutoModeEntryWarning"])
        with open(os.path.join(ctx, "home", ".claude", "settings.json")) as f:
            settings = json.load(f)
        # claude drops the opt-in when the default mode is not auto
        self.assertEqual((settings["permissions"]["defaultMode"], settings["skipAutoPermissionPrompt"]), ("auto", True))
        # every tool call allowed, but those of the owner's claude.ai connectors: refused
        with open(os.path.join(ctx, "home", ".claude", "settings.json")) as f:
            hooks = json.load(f)["hooks"]["PreToolUse"]

        def decision(tool):
            (hook,) = [h for h in hooks if re.search(h["matcher"], tool)]
            out = subprocess.run(["sh", "-c", hook["hooks"][0]["command"]], check=True, stdout=subprocess.PIPE, text=True).stdout
            return json.loads(out)["hookSpecificOutput"]["permissionDecision"]
        self.assertEqual([decision(t) for t in ("Read", "Bash", "mcp__lean__goal", "mcp__claude_ai_Gmail__send")],
                         ["allow", "allow", "allow", "deny"])
        with open(os.path.join(ctx, "root", ".gensokyo-agent", "entrypoint")) as f:
            self.assertIn(f'exec claude --dangerously-skip-permissions {MCP} -- go\n', f.read())
        with open(os.path.join(ctx, "work", "CLAUDE.md")) as f:
            md = f.read()
        for line in ("`notes/a`, a copy: a note", "`sets/d`, a read-only volume", "`scratch`, a volume", "`live`, the owner's own"):
            self.assertIn(line, md)
        self.assertFalse(os.path.exists(work + ".ctx"))
        self.assertNotIn("history", md)

        self.assertEqual(run[1:5], ["run", "--name", "ws1", "--label"])
        self.assertEqual(run[-2:], ["localhost/gensokyo-agent/ws1", "/.gensokyo-agent/entrypoint"])
        joined = " ".join(run)
        for part in (f"-w {work}", "--init", "--device /dev/gpu", "--device /dev/kvm", "--secret k,type=env",
                     "--secret claude-oauth-token,type=env,target=CLAUDE_CODE_OAUTH_TOKEN",
                     f"-v sets-d:{work}/sets/d:ro", f"-v old:{work}/scratch", f"-v {data}:{work}/live", "--memory 4g"):
            self.assertIn(part, joined)

    def staged(self, *path):
        with open(os.path.join(self.out, "ctx", *path)) as f:
            return f.read()

    def test_mcp_json_of_the_agents_own(self):
        self.new("--name", "ws9")
        self.assertEqual(json.loads(self.staged("work", ".mcp.json")), {"mcpServers": {}})
        self.assertIn("`.mcp.json` here is yours", self.staged("work", "CLAUDE.md"))
        self.assertTrue(json.loads(self.staged("home", ".claude", "settings.json"))["enableAllProjectMcpServers"])
        # one given is kept
        own = os.path.join(self.tmp, "own.json")
        with open(own, "w") as f:
            f.write('{"mcpServers": {"a": {"command": "a"}}}')
        self.new("--name", "ws10", "--cp", f"{own}:.mcp.json")
        self.assertIn('"a"', self.staged("work", ".mcp.json"))
        self.new("--name", "ws11", "--", "opencode")
        self.assertFalse(os.path.exists(os.path.join(self.out, "ctx", "work", ".mcp.json")))
        self.assertNotIn("MCP", self.staged("work", "CLAUDE.md"))
        self.assertNotIn("mcp", self.staged("root", ".gensokyo-agent", "entrypoint"))

    def test_each_agent_its_own_login(self):
        settings = os.path.join(self.out, "ctx", "home", ".gemini", "antigravity-cli", "settings.json")
        # agy without its secret: logged out, and never claude's token
        run = " ".join(self.new("--name", "ws12", "--", "agy"))
        self.assertNotIn("--secret", run)
        # its settings, and clearcut nowhere
        with open(settings) as f:
            self.assertEqual(json.load(f), {"colorScheme": "solarized light"})
        self.assertIn("--add-host play.googleapis.com:127.0.0.1", run)
        with mock.patch.dict(os.environ, {"STUB_SECRETS": "gemini-api-key"}):
            run = " ".join(self.new("--name", "ws13", "--", "/bin/agy", "-p", "x"))
            self.assertIn("--secret gemini-api-key,type=env,target=GEMINI_API_KEY", run)
            self.assertNotIn("claude-oauth-token", run)
            with open(settings) as f:
                self.assertEqual(json.load(f), {"colorScheme": "solarized light", "modelProvider": "gemini"})
            # nor the others agy's
            run = " ".join(self.new("--name", "ws14"))
            self.assertIn("--secret claude-oauth-token,type=env,target=CLAUDE_CODE_OAUTH_TOKEN", run)
            self.assertNotIn("gemini", run)
            self.assertNotIn("--add-host", run)
            self.assertFalse(os.path.exists(settings))
            self.assertEqual(json.loads(self.staged("home", ".claude.json"))["theme"], "light-ansi")

    def test_agy_google_login_is_a_file_it_may_rewrite(self):
        # the login first, the key only without it
        with mock.patch.dict(os.environ, {"STUB_SECRETS": "agy-oauth-token gemini-api-key"}):
            run = self.new("--name", "ws20", "--", "agy")
        self.assertIn("agy-oauth-token,type=mount,uid=4738,gid=384,mode=0400", run)
        self.assertNotIn("gemini-api-key", " ".join(run))
        # nor the settings that make agy want the key
        self.assertNotIn("modelProvider", self.staged("home", ".gemini", "antigravity-cli", "settings.json"))
        # copied at the first start, the agent's to rewrite
        secrets, home = os.path.join(self.tmp, "secrets"), os.path.join(self.tmp, "home")
        os.makedirs(secrets)
        os.makedirs(home)
        with open(os.path.join(secrets, "agy-oauth-token"), "w") as f:
            f.write('{"refresh_token": "1//x"}')
        script = self.staged("root", ".gensokyo-agent", "entrypoint").replace("/run/secrets", secrets)
        script = script.replace("exec agy\n", ":\n").replace("/.gensokyo-agent/closure", self.tmp)
        os.makedirs(os.path.join(self.tmp, "share", "gensokyo-agent"))
        with open(os.path.join(self.tmp, "share", "gensokyo-agent", "mcp.json"), "w") as f:
            f.write('{"mcpServers": {}}')
        subprocess.run(["sh", "-c", script], cwd=self.tmp, check=True, env={"HOME": home, "PATH": os.environ["PATH"]})
        token = os.path.join(home, ".gemini", "antigravity-cli", "antigravity-oauth-token")
        with open(token) as f:
            self.assertEqual(f.read(), '{"refresh_token": "1//x"}')
        self.assertEqual(os.stat(token).st_mode & 0o777, 0o600)
        # --legacy: before the agent, there being no first start
        self.enterContext(mock.patch.dict(os.environ, {"STUB_SECRETS": "agy-oauth-token", "XDG_RUNTIME_DIR": self.tmp}))
        self.enterContext(mock.patch("os.getcwd", return_value=self.tmp))
        with quiet():
            agent.run_here(self.conf, ["agy", "-c"])
        (run,) = [c for c in self.calls() if "run" in c]
        self.assertIn("agy-oauth-token,type=mount,uid=4738,gid=384,mode=0400", run)
        self.assertEqual(run[-6:-4], ["sh", "-c"])
        self.assertIn("install -m 600 /run/secrets/agy-oauth-token", run[-4])
        self.assertEqual(run[-3:], ["sh", "agy", "-c"])

    def test_agy_and_codex_have_the_closures_servers_their_way(self):
        # the first start, in the workspace, converts the closure's servers
        closure = os.path.join(self.tmp, "closure")
        os.makedirs(os.path.join(closure, "share", "gensokyo-agent"))
        with open(os.path.join(closure, "share", "gensokyo-agent", "mcp.json"), "w") as f:
            json.dump({"mcpServers": {
                "lean": {"type": "stdio", "command": "/nix/store/x/bin/lean-mcp", "args": ["${PWD}/a"],
                         "env": {"P": "${PWD}/src/p", "D": "${NOPE:-dflt}", "E": "${NOPE}", "L": "$HOME"}},
                "web": {"type": "http", "url": "https://e/${NOPE:-mcp}", "headers": {"A": "b"}},
            }}, f)
        home, ws = os.path.join(self.tmp, "home"), os.path.join(self.tmp, "wsdir")
        os.makedirs(ws)
        lean = {"command": "/nix/store/x/bin/lean-mcp", "args": [ws + "/a"],
                "env": {"P": ws + "/src/p", "D": "dflt", "E": "", "L": "$HOME"}}

        def first_start(name, cmd, path):
            self.new("--name", name, "--", cmd)
            self.assertTrue(os.path.islink(os.path.join(self.out, "ctx", "work", "AGENTS.md")))
            self.assertIn(f"`~/{path}` is yours", self.staged("work", "AGENTS.md"))
            self.assertFalse(os.path.exists(os.path.join(self.out, "ctx", "work", ".mcp.json")))
            script = self.staged("root", ".gensokyo-agent", "entrypoint")
            script = script.replace("/.gensokyo-agent/closure", closure).replace(f"exec {cmd}\n", ":\n")
            # the home as the image has it
            shutil.rmtree(home, ignore_errors=True)
            shutil.copytree(os.path.join(self.out, "ctx", "home"), home)
            subprocess.run(["sh", "-c", script], cwd=ws, check=True, env={"HOME": home, "PATH": os.environ["PATH"]})
            with open(os.path.join(home, path), "rb") as f:
                return f.read()
        self.assertEqual(json.loads(first_start("ws17", "agy", ".gemini/config/mcp_config.json")), {"mcpServers": {
            "lean": lean,
            "web": {"serverUrl": "https://e/mcp", "headers": {"A": "b"}},
        }})
        # after the rest of its config
        self.assertEqual(tomllib.loads(first_start("ws19", "codex", ".codex/config.toml").decode()), {"tui": {"theme": "solarized-light"}, "mcp_servers": {
            "lean": lean,
            "web": {"url": "https://e/mcp", "http_headers": {"A": "b"}},
        }})
        # claude has them by flag, and no such step
        self.new("--name", "ws18")
        self.assertNotIn("jq", self.staged("root", ".gensokyo-agent", "entrypoint"))
        self.assertFalse(os.path.lexists(os.path.join(self.out, "ctx", "work", "AGENTS.md")))

    def test_closure_is_built_and_rooted(self):
        state = os.path.join(self.tmp, "state")
        closure = os.path.join(self.tmp, "closure")
        os.makedirs(os.path.join(closure, "share", "gensokyo-agent"))
        with open(os.path.join(closure, "share", "gensokyo-agent", "mcp.json"), "w") as f:
            json.dump({"mcpServers": {"lean": {"command": "/nix/store/x/bin/lean-mcp"}}}, f)
        self.enterContext(mock.patch.dict(os.environ, {"XDG_STATE_HOME": state, "STUB_CLOSURE": closure}))
        # the root of a workspace that is gone, and of one that may be on its way
        for old in ("gone", "new"):
            os.makedirs(os.path.join(state, "gensokyo-agent", old))
        os.utime(os.path.join(state, "gensokyo-agent", "gone"), (0, 0))
        flake = os.path.join(self.tmp, "flake")
        os.mkdir(flake)
        self.enterContext(contextlib.chdir(flake))
        run = self.new("--name", "ws14", "--closure", ".#lean")
        with open(os.path.join(self.out, "nix")) as f:
            self.assertEqual(json.loads(f.read())[-3:], [
                "--out-link", os.path.join(state, "gensokyo-agent", "ws14", "closure"),
                f"{flake}#agentClosures.x86_64-linux.lean"])
        self.assertEqual(sorted(os.listdir(os.path.join(state, "gensokyo-agent"))), ["new", "ws14"])
        self.assertIn(f"{closure}:/.gensokyo-agent/closure:ro", run)
        self.assertNotIn("/etc/gensokyo-agent/closure:/.gensokyo-agent/closure:ro", run)
        md = self.staged("work", "CLAUDE.md")
        self.assertIn("`lean`: the owner's, from the closure", md)
        self.assertIn("built by the owner from `.#lean`", md)

        # a flake by registry name stays one; #default when no name is given
        self.new("--name", "ws15", "--closure", "nixpkgs")
        with open(os.path.join(self.out, "nix")) as f:
            self.assertEqual(f.read().splitlines()[-1].split(", ")[-1], '"nixpkgs#agentClosures.x86_64-linux.default"]')

        # for library: built here, copied there and rooted there, not here
        os.remove(os.path.join(self.out, "nix"))
        run = self.new("--name", "ws20", "-c", "library", "--closure", ".#lean")
        build, copy = self.calls("nix")
        self.assertNotEqual(os.path.dirname(build[-2]), os.path.join(state, "gensokyo-agent", "ws20"))
        self.assertFalse(os.path.exists(build[-2]))
        self.assertEqual(copy[-3:], ["--to", "ssh-ng://alice@library.example", closure])
        self.assertTrue(self.calls("ssh")[-1][-1].endswith(f" sh ws20 {closure}"))
        self.assertIn(f"{closure}:/.gensokyo-agent/closure:ro", run)
        self.assertFalse(os.path.exists(os.path.join(state, "gensokyo-agent", "ws20")))
        os.environ["STUB_CLOSURE"] = os.path.join(self.tmp, "missing")
        self.dies("--name", "ws16", "--closure", ".")
        # a store path that is not a closure of mkAgentClosure
        os.environ["STUB_CLOSURE"] = os.path.join(self.tmp, "bare")
        os.mkdir(os.environ["STUB_CLOSURE"])
        self.dies("--name", "ws17", "--closure", ".")
        self.assertFalse(os.path.exists(os.path.join(state, "gensokyo-agent", "ws17")))

    def calls(self, prog="podman"):
        with open(os.path.join(self.out, prog)) as f:
            return list(map(json.loads, f))

    def history(self):
        hist = os.path.join(self.tmp, "from")
        proj = os.path.join(hist, "projects", "-p")
        os.makedirs(proj, exist_ok=True)
        with open(os.path.join(proj, "s.jsonl"), "w") as f:
            f.write("{}\n")
        with open(os.path.join(hist, "settings.json"), "w") as f:
            f.write("{}")
        os.environ["STUB_FROM"] = hist

    def test_from_carries_on_the_conversation(self):
        self.history()
        top = self.repo()
        # from here to library, under another name, the conversation only
        run = self.new("--name", "ws18", "-c", "library", "--from", "old", "--no-copy", "--git", f"{top}::", "--prompt", "go on")
        older = os.path.join(self.base, "older")
        self.assertIn(["cp", "old:/home/agent/.claude", os.path.join(self.base, "ws18.ctx", "home", ".claude")], self.calls())
        self.assertNotIn("stop", [c[0] for c in self.calls()])
        self.assertEqual(self.staged("home", ".claude", "projects", "-p", "s.jsonl"), "{}\n")
        # this workspace's settings, not the old one's
        self.assertEqual(json.loads(self.staged("home", ".claude", "settings.json"))["permissions"]["defaultMode"], "auto")
        self.assertTrue(json.loads(self.staged("home", ".claude.json"))["projects"][older]["hasTrustDialogAccepted"])
        with open(os.path.join(self.out, "Containerfile")) as f:
            self.assertIn(f"COPY --chown=4738:384 work/ {older}/\n", f.read())
        self.assertIn(f"-w {older}", " ".join(run))
        self.assertEqual(run[1:5], ["-c", "library", "run", "--name"])
        self.assertEqual(run[run.index("--name") + 1], "ws18")
        self.assertTrue(git(top, "config", "remote.ws18.url").endswith(f" sh ws18 %S {older}/src/proj podman -c library"))
        entry = self.staged("root", ".gensokyo-agent", "entrypoint")
        self.assertIn(f"exec claude --dangerously-skip-permissions {MCP} --continue -- 'go on'\n", entry)
        md = self.staged("work", "CLAUDE.md")
        self.assertIn("conversation so far is that of the workspace `old`", md)
        self.assertIn("on another machine", md)
        self.assertIn("Its files are not here", md)
        # its closure was the default one: that of library then, and nothing copied
        self.assertIn("/etc/gensokyo-agent/closure:/.gensokyo-agent/closure:ro", run)
        self.assertFalse(os.path.exists(os.path.join(self.out, "nix")))
        self.assertFalse(os.path.exists(os.path.join(self.base, "ws18.ctx")))
        # no --continue for another agent; its home comes along all the same
        self.new("--name", "ws19", "--from", "old", "--", "codex")
        self.assertNotIn("--continue", self.staged("root", ".gensokyo-agent", "entrypoint"))
        self.dies("--from", "bare")
        self.dies("--from", "nowhere")
        self.dies("--from", "library/old")
        self.dies("--copy")
        # old is on this host, its name taken
        self.dies("--from", "lib", "-c", "library")

    def carried(self):
        """rec's workspace: an uncommitted file, a checkout, a volume's mount
        point and the CLAUDE.md of the owner's and the wrapper's"""
        work = os.path.join(self.tmp, "recwork")
        clone = os.path.join(work, "src", "proj")
        os.makedirs(os.path.join(clone, ".git"))
        os.makedirs(os.path.join(work, "data"))
        with open(os.path.join(work, "data", "big"), "w") as f:
            f.write("volume")
        with open(os.path.join(work, "u"), "w") as f:
            f.write("uncommitted")
        with open(os.path.join(work, "CLAUDE.md"), "w") as f:
            f.write("the owner's\n# workspace rec\n\nstale\n")
        with open(os.path.join(work, ".mcp.json"), "w") as f:
            f.write('{"mcpServers": {"mine": {}}}')
        os.environ["STUB_WORK"] = work
        closure = os.path.join(self.tmp, "rec-closure")
        os.mkdir(closure)
        os.environ["STUB_REC_CLOSURE"] = closure
        state = os.path.join(self.tmp, "state")
        os.environ["XDG_STATE_HOME"] = state
        return closure, os.path.join(state, "gensokyo-agent")

    def test_from_replaces_it_on_its_host(self):
        self.history()
        closure, roots = self.carried()
        top = self.repo()
        recdir = os.path.join(self.base, "rec")
        start = self.new("--from", "rec", "--git-add-remote", top)
        calls = self.calls()
        # stopped, then copied whole
        self.assertLess(calls.index(["stop", "rec"]), calls.index(["cp", "rec:" + recdir, os.path.join(self.base, "rec.ctx", "work")]))
        self.assertEqual(self.staged("work", "u"), "uncommitted")
        self.assertTrue(os.path.isdir(os.path.join(self.out, "ctx", "work", "src", "proj", ".git")))
        # but not what was mounted there
        self.assertFalse(os.path.exists(os.path.join(self.out, "ctx", "work", "data")))
        self.assertEqual(json.loads(self.staged("work", ".mcp.json")), {"mcpServers": {"mine": {}}})
        md = self.staged("work", "CLAUDE.md")
        self.assertTrue(md.startswith("the owner's\n# workspace rec\n"), md)
        self.assertNotIn("stale", md)
        self.assertEqual(md.count("# workspace"), 1)
        self.assertIn("Its files came along", md)
        self.assertNotIn("another machine", md)
        self.assertIn("`src/proj`, a checkout as `rec` left it", md)
        self.assertIn("the one `rec` had", md)
        self.assertIn("`lean`: the owner's, from the closure", md)
        # its closure, rooted here under its name
        self.assertEqual(self.calls("nix")[-1][-3:], ["--out-link", os.path.join(roots, "rec", "closure"), closure])
        self.assertNotIn("copy", self.calls("nix")[-1])
        # the old one steps aside, the new one is made, and the old one goes
        verbs = [c[0] for c in calls]
        i = verbs.index("rename")
        self.assertEqual(verbs[i:i + 4], ["rename", "create", "rm", "rmi"])
        self.assertEqual((calls[i], calls[i + 2], calls[i + 3]), (["rename", "rec", "rec.replaced"], ["rm", "rec.replaced"], ["rmi", "0ld1mage"]))
        create = calls[i + 1]
        self.assertEqual(create[create.index("--name") + 1], "rec")
        self.assertIn(f"{closure}:/.gensokyo-agent/closure:ro", create)
        self.assertEqual(create[-2:], ["localhost/gensokyo-agent/rec", "/.gensokyo-agent/entrypoint"])
        record = json.loads(create[create.index("gensokyo-agent=rec") + 2].split("=", 1)[1])
        self.assertEqual((record["closure"], record["servers"]), (closure, ["lean"]))
        self.assertNotIn("git_add_remote", record["opts"])
        self.assertEqual(start[1:], ["start", "-a", "rec"])
        # the remote, only that: the checkout is the one that came along
        url = git(top, "config", "remote.rec.url")
        self.assertTrue(url.endswith(f" sh rec %S {recdir}/src/proj podman"), url)
        self.assertEqual(git(top, "config", "remote.rec.push"), "refs/heads/*:refs/remotes/owner/*")
        # the same remote again is no change; one elsewhere is not replaced
        self.new("--from", "rec", "--git-add-remote", top)
        self.dies("--from", "rec", "-c", "library", "--git-add-remote", top)
        self.assertEqual(git(top, "config", "remote.rec.url"), url)
        # nor is there a checkout to point at without its files
        git(top, "remote", "remove", "rec")
        self.dies("--from", "rec", "--no-copy", "--git-add-remote", top)
        self.assertEqual(git(top, "remote"), "")

    def test_from_another_host(self):
        self.history()
        closure, roots = self.carried()
        # from here to library: its closure goes there and is rooted there
        run = self.new("-c", "library", "--from", "rec")
        self.assertEqual(run[1:4], ["-c", "library", "run"])
        self.assertEqual(run[run.index("--name") + 1], "rec")
        self.assertIn(f"{closure}:/.gensokyo-agent/closure:ro", run)
        self.assertIn(["stop", "rec"], self.calls())
        self.assertNotIn("rename", [c[0] for c in self.calls()])
        (copy,) = self.calls("nix")
        self.assertEqual(copy[-4:], ["--no-check-sigs", "--to", "ssh-ng://alice@library.example", closure])
        self.assertEqual(self.calls("nixenv"), ["-p 2222 -i /id"])
        ssh = self.calls("ssh")[-1]
        self.assertEqual(ssh[:5], ["-p", "2222", "-i", "/id", "alice@library.example"])
        self.assertTrue(ssh[5].startswith("sh -c ") and ssh[5].endswith(f" sh rec {closure}"), ssh[5])
        self.assertFalse(os.path.exists(os.path.join(roots, "rec")))
        md = self.staged("work", "CLAUDE.md")
        self.assertIn("on another machine", md)
        self.assertIn("a `result` link", md)
        # and from library to here, by way of its connection
        os.remove(os.path.join(self.out, "nix"))
        run = self.new("--from", "library/lib", "--no-copy")
        self.assertEqual(run[1:3], ["run", "--name"])
        self.assertEqual(run[run.index("--name") + 1], "lib")
        self.assertIn(["-c", "library", "cp", "lib:/home/agent/.claude", os.path.join(self.base, "lib.ctx", "home", ".claude")], self.calls())
        copy, root = self.calls("nix")
        self.assertEqual(copy[-3:], ["--from", "ssh-ng://alice@library.example", closure])
        self.assertEqual(root[-3:], ["--out-link", os.path.join(roots, "lib", "closure"), closure])

    def conversations(self):
        projects = os.path.join(self.tmp, "projects-NAME")
        said = {"rec": "<command-name>/x</command-name>", "lib": "on library"}
        for n in ("rec", "lib"):
            sess = os.path.join(projects.replace("NAME", n), "-var-tmp-gensokyo-agent-" + n)
            os.makedirs(sess)
            with open(os.path.join(sess, "s" + n + ".jsonl"), "w") as f:
                for line in ({"type": "summary"}, {"type": "user", "isMeta": True, "message": {"content": "meta"}},
                             {"type": "user", "message": {"content": said[n]}},
                             {"type": "user", "message": {"content": [{"type": "text", "text": "hi\n  claude, " + n}]}}):
                    f.write(json.dumps(line) + "\n")
            os.utime(os.path.join(sess, "s" + n + ".jsonl"), (1e9 if n == "lib" else 2e9,) * 2)
            # what is not a transcript is not listed
            os.makedirs(os.path.join(sess, "s" + n, "tool-results"))
            with open(os.path.join(sess, "s" + n, "tool-results", "t.txt"), "w") as f:
                f.write("x")
        home = os.path.join(self.tmp, "home")
        os.makedirs(os.path.join(home, ".claude", "projects", "-mine"))
        with open(os.path.join(home, ".claude", "projects", "-mine", "m.jsonl"), "w") as f:
            f.write(json.dumps({"type": "user", "message": {"content": "mine"}}) + "\n")
        os.utime(os.path.join(home, ".claude", "projects", "-mine", "m.jsonl"), (3e9, 3e9))
        self.enterContext(mock.patch.dict(os.environ, {"STUB_PROJECTS": projects, "HOME": home}))
        os.environ.pop("XDG_DATA_HOME", None)
        return projects

    def test_history_lists_every_conversation(self):
        self.conversations()
        with contextlib.redirect_stdout(io.StringIO()) as out, quiet():
            agent.list_history(self.conf, [])
        lines = out.getvalue().splitlines()
        # oldest first; the first thing the owner said, not a command; pipe is here again
        self.assertEqual([ln.split()[2:] for ln in lines], [
            ["library/lib", "0.0M", "slib", "on", "library"],
            ["local/rec", "0.0M", "srec", "hi", "claude,", "rec"],
            ["local/_owner", "0.0M", "m", "mine"]])
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "home", ".local")))
        with contextlib.redirect_stdout(io.StringIO()) as out, quiet():
            agent.list_history(self.conf, ["-c", "library"])
        self.assertEqual([ln.split()[2] for ln in out.getvalue().splitlines()], ["library/lib", "local/_owner"])

    def test_copy_history_gathers_every_conversation(self):
        projects = self.conversations()
        dest = os.path.join(self.tmp, "hist")
        os.makedirs(os.path.join(dest, "local", "gone", "projects"))
        with quiet():
            agent.copy_history(self.conf, [dest])
        rec = os.path.join(dest, "local", "rec", "projects", "-var-tmp-gensokyo-agent-rec", "srec.jsonl")
        self.assertTrue(os.path.isfile(rec))
        self.assertTrue(os.path.isfile(os.path.join(dest, "local", "rec", "projects", "-var-tmp-gensokyo-agent-rec", "srec", "tool-results", "t.txt")))
        self.assertTrue(os.path.isfile(os.path.join(dest, "library", "lib", "projects", "-var-tmp-gensokyo-agent-lib", "slib.jsonl")))
        with open(os.path.join(dest, "local", "_owner", "projects", "-mine", "m.jsonl")) as f:
            self.assertIn("mine", f.read())
        # pipe is here again: once; old has none; what was gathered before stays
        self.assertFalse(os.path.exists(os.path.join(dest, "pipe")))
        self.assertEqual(sorted(os.listdir(os.path.join(dest, "local"))), ["_owner", "gone", "rec"])
        self.assertEqual([n for n in os.listdir(dest) if n.startswith(".")], [])
        # a transcript grown since is taken again
        with open(os.path.join(projects.replace("NAME", "rec"), "-var-tmp-gensokyo-agent-rec", "srec.jsonl"), "a") as f:
            f.write("more\n")
        with quiet():
            agent.copy_history(self.conf, [dest])
        with open(rec) as f:
            self.assertTrue(f.read().endswith("more\n"))
        # the default place
        with quiet():
            agent.copy_history(self.conf, ["-c", "library"])
        self.assertTrue(os.path.isdir(os.path.join(self.tmp, "home", ".local", "share", "gensokyo-agent", "history", "library", "lib")))

    def test_root_script_parses(self):
        subprocess.run(["sh", "-n", "-c", agent.ROOT], check=True)

    def test_connection_reaches_every_podman_call(self):
        run = self.new("--name", "ws2", "-c", "library")
        self.assertEqual(run[1:4], ["-c", "library", "run"])
        with open(os.path.join(self.out, "podman")) as f:
            for call in map(json.loads, f):
                self.assertEqual(call[:2], ["-c", "library"])

    def test_ports(self):
        run = " ".join(self.new("--name", "ws5", "-p", "9000", "--publish", "127.0.0.1:9001:9001",
                                "-p8080:80", "-sp", "8800", "-p", "9002/udp"))
        # a port alone is that port here too
        self.assertIn("-p 9000:9000 -p 127.0.0.1:9001:9001 -p 8080:80 -p 9002:9002/udp -p 127.0.0.1:8800:8800", run)
        self.assertFalse(os.path.exists(os.path.join(self.out, "ssh")))

        run = " ".join(self.new("--name", "ws6", "-c", "library", "-sp", "8800", "-L", "1:h:2"))
        self.assertIn("-p 127.0.0.1:8800:8800", run)
        with open(os.path.join(self.out, "ssh")) as f:
            ssh = json.loads(f.read())
        self.assertEqual(ssh[:2], ["-f", "-N"])
        self.assertEqual(ssh[-9:], ["-L", "1:h:2", "-L", "8800:127.0.0.1:8800", "-p", "2222", "-i", "/id", "alice@library.example"])

        self.dies("-L", "1:h:2")
        self.dies("-sp", "http")
        self.dies("-c", "pipe", "-sp", "8800")
        self.dies("-c", "nowhere", "-sp", "8800")

    def test_refusals(self):
        data = os.path.join(self.tmp, "data")
        os.mkdir(data)
        self.dies("-c", "library", "--bind", f"{data}:live")
        self.dies("--name", "Ws")
        self.dies("--name", "old")
        self.dies("--cp", f"{data}:x", "--cp", f"{data}:x")

    def test_generated_name(self):
        name = self.new()[3]
        self.assertRegex(name, r"^[a-z]+_[a-z]+$")
        left, right = name.split("_")
        self.assertIn(left, agent.ADJECTIVES)
        self.assertIn(right, agent.SURNAMES)
        self.assertEqual((len(agent.ADJECTIVES), len(agent.SURNAMES)), (108, 236))
        with mock.patch("random.choice", side_effect=["boring", "wozniak", "boring", "turing"]):
            self.assertEqual(agent.random_name(), "boring_turing")

    def test_devices_are_asked_for(self):
        self.assertNotIn("/dev/kvm", self.new("--no-vm"))
        self.assertIn("/dev/kvm", self.new())
        self.assertIn("/etc/gensokyo-agent/closure:/.gensokyo-agent/closure:ro", self.new())
        self.assertNotIn("/dev/gpu", self.new())

    def test_device_with_the_owners_groups(self):
        self.conf["vmArgs"] = ["--group-add", "302", "--device", "/dev/kvm"]
        run = self.new("--name", "ws12", "-d", "/dev/ttyUSB0", "--device", "/dev/dri/renderD128:/dev/dri/renderD128:rw", "--memory", "4g")
        self.assertEqual(run[run.index("--group-add"):run.index("--secret")],
                         ["--group-add", "keep-groups", "--device", "/dev/ttyUSB0", "--device", "/dev/dri/renderD128:/dev/dri/renderD128:rw"])
        self.assertEqual(run.count("--group-add"), 1)
        self.assertIn("/dev/kvm", run)
        self.assertIn("--memory", run)
        run = self.new("--name", "ws13")
        self.assertEqual(run[run.index("--group-add"):][:4], ["--group-add", "302", "--device", "/dev/kvm"])
        self.assertNotIn("keep-groups", run)

    def test_git_forms(self):
        top = self.repo()
        git(top, "checkout", "-q", "-b", "topic")

        def form(spec):
            g = agent.parse_git(self.conf, spec)
            return g["base"], g["branch"], g["full"]
        self.assertEqual(form(top), ("topic", "topic", False))
        self.assertEqual(form(f"{top}:master"), ("master", "master", False))
        self.assertEqual(form(f"{top}:master:"), ("master", "master", False))
        # the workspace's branch is master, whatever it started from
        self.assertEqual(form(f"{top}::"), ("topic", "master", False))
        self.assertEqual(form(f"@{top}:v1:fix"), ("v1", "fix", True))
        for bad in (f"{top}:v1", f"{top}:nope", self.tmp, f"{top}:a:b:c"):
            with self.assertRaises(SystemExit), quiet():
                agent.parse_git(self.conf, bad)

    def test_git_clone_and_remote(self):
        top = self.repo()
        git(top, "branch", "topic")
        run = self.new("--name", "ws3", "-c", "library", "--git", f"{top}:topic:")
        work = os.path.join(self.base, "ws3")
        clone = os.path.join(self.out, "ctx", "work", "src", "proj")
        self.assertEqual(git(clone, "symbolic-ref", "--short", "HEAD"), "master")
        self.assertEqual(git(clone, "rev-parse", "HEAD"), git(top, "rev-parse", "topic"))
        self.assertEqual(git(clone, "rev-parse", "owner/topic"), git(top, "rev-parse", "topic"))
        self.assertEqual(git(clone, "rev-list", "--count", "HEAD"), "1")
        self.assertEqual(git(clone, "remote"), "")
        self.assertEqual(git(clone, "status", "--porcelain"), "")
        url = git(top, "config", "remote.ws3.url")
        self.assertTrue(url.startswith("ext::sh -c n=$1% s=$2% d=$3;% shift% 3;% up=$("), url)
        self.assertTrue(url.endswith(f" sh ws3 %S {work}/src/proj podman -c library"), url)
        self.assertEqual(git(top, "config", "remote.ws3.push"), "refs/heads/*:refs/remotes/owner/*")
        self.assertEqual(git(top, "config", "protocol.ext.allow"), "user")
        with open(os.path.join(self.out, "ctx", "work", "CLAUDE.md")) as f:
            self.assertIn("`src/proj`, on `master`, started from the owner's `topic`", f.read())
        self.assertEqual(run[3], "run")
        # the name is a remote of the checkout now
        self.dies("--name", "ws3", "--git", top)

    def test_git_full_history(self):
        top = self.repo()
        self.new("--name", "ws4", "--git", f"@{top}")
        clone = os.path.join(self.out, "ctx", "work", "src", "proj")
        self.assertEqual(git(clone, "rev-list", "--count", "HEAD"), "3")
        self.assertEqual(git(clone, "symbolic-ref", "--short", "HEAD"), "master")


if __name__ == "__main__":
    unittest.main()
