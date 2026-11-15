import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import agent

# a podman that says nothing exists but the token secret, and keeps what it was given
STUB = """#!{python}
import json, os, shutil, sys
args = sys.argv[1:]
out = os.environ["STUB_OUT"]
with open(os.path.join(out, os.path.basename(sys.argv[0])), "a") as f:
    f.write(json.dumps(args) + "\\n")
if "connection" in args:
    print(json.dumps([{{"Name": "library", "URI": "ssh://alice@library.example:2222/run/user/1000/podman/podman.sock", "Identity": "/id"}},
                      {{"Name": "pipe", "URI": "unix:///run/podman.sock"}}]))
if "exists" in args:
    sys.exit(0 if args[-1] in ("claude-oauth-token", "old") else 1)
if "build" in args:
    shutil.rmtree(os.path.join(out, "ctx"), ignore_errors=True)
    shutil.copytree(args[-1], os.path.join(out, "ctx"), symlinks=True)
    shutil.move(os.path.join(out, "ctx", "Containerfile"), os.path.join(out, "Containerfile"))
"""


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
        root = os.path.join(self.tmp, "rootfs")
        os.makedirs(os.path.join(root, "home", "agent"))
        self.conf = {
            "podman": podman,
            "git": "git",
            "ssh": ssh,
            "defaultCmd": "claude --dangerously-skip-permissions",
            "token": {"secret": "claude-oauth-token", "target": "CLAUDE_CODE_OAUTH_TOKEN"},
            "hereArgs": ["--rm"],
            "flavors": {
                "nix": {"containerfile": "FROM scratch\n", "root": root, "user": "4738:384",
                        "home": "/home/agent", "runArgs": ["--init"], "gpuArgs": ["--device", "/dev/gpu"], "vm": True, "vmArgs": ["--device", "/dev/kvm"]},
                "alpine": {"containerfile": "FROM alpine\n", "root": None, "user": "0:0",
                           "home": "/root", "runArgs": [], "gpuArgs": None, "vm": False, "vmArgs": ["--device", "/dev/kvm-alpine"]},
            },
        }
        self.base = os.path.join(self.tmp, "ws")
        self.enterContext(mock.patch.dict(os.environ, {
            "STUB_OUT": self.out, "GENSOKYO_AGENT_TMPDIR": self.base,
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
        self.assertIn("--model 'some-new-model[1m]' --effort xhigh -- go\n", entry)
        self.assertIn("--model 'some-new-model[1m]' --effort xhigh --continue && exit\n", entry)
        self.new("--name", "ws8")
        with open(os.path.join(self.out, "ctx", "root", ".gensokyo-agent", "entrypoint")) as f:
            self.assertNotIn("--model", f.read())
        self.dies("--model", "opus", "--", "codex")

    def test_entrypoint_resumes_claude_only(self):
        claude = agent.entrypoint(["claude", "--x"], "it's time")
        self.assertIn("claude --x --continue && exit", claude)
        # a list flag of claude's would take the prompt for one more of its words
        self.assertIn("exec claude --x -- 'it'\"'\"'s time'", claude)
        self.assertNotIn("--continue", agent.entrypoint(["codex"], None))
        self.assertIn("exec codex go\n", agent.entrypoint(["codex"], "go"))

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
            self.assertTrue(json.load(f)["projects"][work]["hasTrustDialogAccepted"])
        with open(os.path.join(ctx, "root", ".gensokyo-agent", "entrypoint")) as f:
            self.assertIn("exec claude --dangerously-skip-permissions -- go\n", f.read())
        with open(os.path.join(ctx, "work", "CLAUDE.md")) as f:
            md = f.read()
        for line in ("`notes/a`, a copy: a note", "`sets/d`, a read-only volume", "`scratch`, a volume", "`live`, the owner's own"):
            self.assertIn(line, md)
        self.assertFalse(os.path.exists(work + ".ctx"))

        self.assertEqual(run[1:5], ["run", "--name", "ws1", "--label"])
        self.assertEqual(run[-2:], ["localhost/gensokyo-agent/ws1", "/.gensokyo-agent/entrypoint"])
        joined = " ".join(run)
        for part in (f"-w {work}", "--init", "--device /dev/gpu", "--device /dev/kvm", "--secret k,type=env",
                     "--secret claude-oauth-token,type=env,target=CLAUDE_CODE_OAUTH_TOKEN",
                     f"-v sets-d:{work}/sets/d:ro", f"-v old:{work}/scratch", f"-v {data}:{work}/live", "--memory 4g"):
            self.assertIn(part, joined)

    def test_connection_reaches_every_podman_call(self):
        run = self.new("--name", "ws2", "-c", "library", "--flavor", "alpine")
        self.assertEqual(run[1:4], ["-c", "library", "run"])
        with open(os.path.join(self.out, "podman")) as f:
            for call in map(json.loads, f):
                self.assertEqual(call[:2], ["-c", "library"])
        self.assertFalse(os.path.exists(os.path.join(self.out, "ctx", "root", "home")))

    def test_ports(self):
        run = " ".join(self.new("--name", "ws5", "-p", "9000", "-sp", "8800"))
        self.assertIn("-p 9000 -p 127.0.0.1:8800:8800", run)
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
        self.dies("--flavor", "alpine", "--gpu")
        self.dies("--flavor", "debian")
        self.dies("-c", "library", "--bind", f"{data}:live")
        self.dies("--name", "Ws")
        self.dies("--name", "old")
        self.dies("--cp", f"{data}:x", "--cp", f"{data}:x")

    def test_generated_name(self):
        name = self.new()[3]
        self.assertRegex(name, r"^[a-z]+_[a-z]+$")

    def test_devices_are_asked_for(self):
        self.assertNotIn("/dev/kvm", self.new("--no-vm"))
        self.assertNotIn("/dev/kvm-alpine", self.new("--flavor", "alpine"))
        self.assertIn("/dev/kvm-alpine", self.new("--flavor", "alpine", "--vm"))
        self.assertNotIn("/dev/gpu", self.new())

    def test_git_forms(self):
        top = self.repo()
        git(top, "checkout", "-q", "-b", "topic")

        def form(spec):
            g = agent.parse_git(self.conf, spec, "ws")
            return g["base"], g["branch"], g["full"]
        self.assertEqual(form(top), ("topic", "topic", False))
        self.assertEqual(form(f"{top}:master"), ("master", "master", False))
        self.assertEqual(form(f"{top}:master:"), ("master", "ws", False))
        self.assertEqual(form(f"{top}::"), ("topic", "ws", False))
        self.assertEqual(form(f"@{top}:v1:fix"), ("v1", "fix", True))
        for bad in (f"{top}:v1", f"{top}:nope", self.tmp, f"{top}:a:b:c"):
            with self.assertRaises(SystemExit), quiet():
                agent.parse_git(self.conf, bad, "ws")

    def test_git_clone_and_remote(self):
        top = self.repo()
        run = self.new("--name", "ws3", "-c", "library", "--git", f"{top}:master:")
        work = os.path.join(self.base, "ws3")
        clone = os.path.join(self.out, "ctx", "work", "src", "proj")
        self.assertEqual(git(clone, "symbolic-ref", "--short", "HEAD"), "ws3")
        self.assertEqual(git(clone, "rev-parse", "HEAD"), git(top, "rev-parse", "master"))
        self.assertEqual(git(clone, "rev-parse", "owner/master"), git(top, "rev-parse", "master"))
        self.assertEqual(git(clone, "rev-list", "--count", "HEAD"), "1")
        self.assertEqual(git(clone, "remote"), "")
        self.assertEqual(git(clone, "status", "--porcelain"), "")
        url = git(top, "config", "remote.ws3.url")
        self.assertTrue(url.startswith("ext::sh -c n=$1% s=$2% d=$3;% shift% 3;% up=$("), url)
        self.assertTrue(url.endswith(f" sh ws3 %S {work}/src/proj podman -c library"), url)
        self.assertEqual(git(top, "config", "remote.ws3.push"), "refs/heads/*:refs/remotes/owner/*")
        self.assertEqual(git(top, "config", "protocol.ext.allow"), "user")
        with open(os.path.join(self.out, "ctx", "work", "CLAUDE.md")) as f:
            self.assertIn("`src/proj`, on `ws3`, started from the owner's `master`", f.read())
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
