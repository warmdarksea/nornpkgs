import contextlib
import json
import os
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
with open(os.path.join(out, "calls"), "a") as f:
    f.write(json.dumps(args) + "\\n")
if "exists" in args:
    sys.exit(0 if args[-1] in ("claude-oauth-token", "old") else 1)
if "build" in args:
    shutil.copytree(args[-1], os.path.join(out, "ctx"), symlinks=True)
    shutil.move(os.path.join(out, "ctx", "Containerfile"), out)
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
        root = os.path.join(self.tmp, "rootfs")
        os.makedirs(os.path.join(root, "home", "agent"))
        self.conf = {
            "podman": podman,
            "git": "git",
            "defaultCmd": "claude --dangerously-skip-permissions",
            "token": {"secret": "claude-oauth-token", "target": "CLAUDE_CODE_OAUTH_TOKEN"},
            "hereArgs": ["--rm"],
            "flavors": {
                "nix": {"containerfile": "FROM scratch\n", "root": root, "user": "4738:384",
                        "home": "/home/agent", "runArgs": ["--init"], "gpuArgs": ["--device", "/dev/gpu"]},
                "alpine": {"containerfile": "FROM alpine\n", "root": None, "user": "0:0",
                           "home": "/root", "runArgs": [], "gpuArgs": None},
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
        """Run --new-ws up to the podman run it would exec; returns that argv."""
        opts, cmd, passthrough = agent.parse_args(["--new-ws", *argv])
        with mock.patch("os.execvp") as execvp, quiet():
            agent.new_workspace(self.conf, opts, cmd, passthrough)
        return execvp.call_args[0][1]

    def dies(self, *argv):
        with self.assertRaises(SystemExit), quiet():
            self.new(*argv)

    def test_plain_invocation_is_left_alone(self):
        self.assertEqual(agent.parse_args(["codex", "--foo"]), (None, ["codex", "--foo"], []))
        self.assertEqual(agent.parse_args([]), (None, [], []))

    def test_flags_command_and_passthrough(self):
        opts, cmd, passthrough = agent.parse_args(
            ["--new-ws", "--memory", "4g", "-c", "library", "-s", "k,type=env", "--", "codex", "--new-ws"])
        self.assertEqual((opts.connection, opts.secret), ("library", ["k,type=env"]))
        self.assertEqual(cmd, ["codex", "--new-ws"])
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

    def test_entrypoint_resumes_claude_only(self):
        claude = agent.entrypoint(["claude", "--x"], "it's time")
        self.assertIn("claude --x --continue && exit", claude)
        self.assertIn("exec claude --x 'it'\"'\"'s time'", claude)
        self.assertNotIn("--continue", agent.entrypoint(["codex"], None))

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
            self.assertIn("exec claude --dangerously-skip-permissions go\n", f.read())
        with open(os.path.join(ctx, "work", "CLAUDE.md")) as f:
            md = f.read()
        for line in ("`notes/a`, a copy: a note", "`sets/d`, a read-only volume", "`scratch`, a volume", "`live`, the owner's own"):
            self.assertIn(line, md)
        self.assertFalse(os.path.exists(work + ".ctx"))

        self.assertEqual(run[1:5], ["run", "--name", "ws1", "--label"])
        self.assertEqual(run[-2:], ["localhost/gensokyo-agent/ws1", "/.gensokyo-agent/entrypoint"])
        joined = " ".join(run)
        for part in (f"-w {work}", "--init", "--device /dev/gpu", "--secret k,type=env",
                     "--secret claude-oauth-token,type=env,target=CLAUDE_CODE_OAUTH_TOKEN",
                     f"-v sets-d:{work}/sets/d:ro", f"-v old:{work}/scratch", f"-v {data}:{work}/live", "--memory 4g"):
            self.assertIn(part, joined)

    def test_connection_reaches_every_podman_call(self):
        run = self.new("--name", "ws2", "-c", "library", "--flavor", "alpine")
        self.assertEqual(run[1:4], ["-c", "library", "run"])
        with open(os.path.join(self.out, "calls")) as f:
            for call in map(json.loads, f):
                self.assertEqual(call[:2], ["-c", "library"])
        self.assertFalse(os.path.exists(os.path.join(self.out, "ctx", "root", "home")))

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
        self.assertEqual(git(top, "config", "remote.ws3.url"),
                         f"ext::podman -c library exec -i ws3 %S {work}/src/proj")
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
