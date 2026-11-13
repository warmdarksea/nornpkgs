import argparse
import json
import os
import random
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

USAGE = """\
gensokyo-agent [CMD...]                  CMD (default: claude) in a throwaway
                                         sandbox on the current directory
gensokyo-agent --new-ws [FLAG...] [-- CMD...]
                                         a workspace: a directory assembled from
                                         local files, built into an image and
                                         run as a container that stays
  --name NAME                 container and image name (default: generated)
  --flavor nix|alpine         nix (default): this host's store and nix daemon,
                              on hosts with the gensokyo-agent module.
                              alpine: a stock image, root, any podman host
  -c, --connection NAME       podman connection to build and run on
  -s, --secret SPEC           as podman run --secret
  --gpu                       the nvidia devices and CUDA
  --git [@]PATH[:BASE[:[NEW]]]
                              clone the checkout at PATH into src/, one
                              commit deep (@: all of it), and give PATH a
                              remote NAME to fetch the work from. BASE: the
                              branch to be on, default the current one.
                              NEW: a branch to start from it, default NAME
  --cp SRC:DST[:DESC]         copy SRC to DST in the workspace
  --ro [VOL=]SRC:DST[:DESC]   a volume seeded from SRC at DST, read-only;
  --rw [VOL=]SRC:DST[:DESC]   or writable. volumes outlive the workspace,
                              and one that exists is used as it is
  --bind SRC:DST[:DESC]       SRC itself at DST; local only
  --prompt TEXT               what the agent starts on
  anything else               goes to podman run
DST is relative to the workspace; DESC ends up in its CLAUDE.md.
"""

ADJECTIVES = """amber brisk calm cosy dapper eager fuzzy gentle hazy idle
jolly keen lucid mellow nimble odd plucky quiet rosy sleepy tidy upbeat vivid
wistful zesty""".split()
NOUNS = """badger comet dumpling ember fennel gecko heron iris jackdaw kettle
lantern marmot nettle otter pebble quince rook sparrow thistle urchin vole
walnut yarrow zephyr""".split()

NAME_RE = r"[a-z0-9][a-z0-9_.-]*"


def load_conf():
    with open(os.environ.get("GENSOKYO_AGENT_CONF", "@conf@")) as f:
        conf = json.load(f)
    conf["podman"] = os.environ.get("GENSOKYO_AGENT_PODMAN", conf["podman"])
    return conf


def say(msg):
    print(f"gensokyo-agent: {msg}", file=sys.stderr)


def copy_writable(src, dst):
    """Copy a store tree to somewhere we own; store modes are read-only."""
    shutil.copytree(src, dst, symlinks=True, dirs_exist_ok=True)
    for d, _, files in os.walk(dst):
        for p in [d] + [os.path.join(d, f) for f in files]:
            if not os.path.islink(p):
                os.chmod(p, os.stat(p).st_mode | 0o200)


def write_home(home, workdir):
    """The sandbox has no home of its own to remember the first-run dialogs."""
    os.makedirs(os.path.join(home, ".claude"), exist_ok=True)
    with open(os.path.join(home, ".claude.json"), "w") as f:
        json.dump({
            "hasCompletedOnboarding": True,
            "projects": {workdir: {"hasTrustDialogAccepted": True}},
        }, f)
    with open(os.path.join(home, ".claude", "settings.json"), "w") as f:
        json.dump({"skipDangerousModePermissionPrompt": True}, f)


def token_args(conf, podman):
    token = conf["token"]
    if subprocess.call([*podman, "secret", "exists", token["secret"]], stdout=subprocess.DEVNULL) != 0:
        say(f"no podman secret {token['secret']} here, the agent starts logged out; "
            f"create it from `claude setup-token` with: {' '.join(podman)} secret create {token['secret']} -")
        return []
    return ["--secret", f"{token['secret']},type=env,target={token['target']}"]


def die(msg):
    say(msg)
    sys.exit(2)


def remove_tree(path):
    def retry(func, p, _):
        os.chmod(os.path.dirname(p), 0o700)
        os.chmod(p, 0o700)
        func(p)
    shutil.rmtree(path, onexc=retry)


def run_here(conf, cmd):
    """One command in a throwaway sandbox, the current directory mounted."""
    podman = [conf["podman"]]
    debug = os.environ.get("DEBUG", "0") == "1"
    cmd = cmd or os.environ.get("AGENT_CMD", conf["defaultCmd"]).split()
    cwd = os.getcwd()
    nix = conf["flavors"]["nix"]

    # rootless podman can't write into a root-owned store path (unmapped uid,
    # no DAC override in the userns), so stage the skeleton somewhere we own
    base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "gensokyo-agent")
    os.makedirs(base, exist_ok=True)
    root = tempfile.mkdtemp(prefix="root.", dir=base)
    try:
        copy_writable(nix["root"], root)
        os.chmod(root, 0o755)  # mkdtemp gives 0700; / must be traversable by the agent uid
        home = root + nix["home"]
        write_home(home, cwd)

        args = conf["hereArgs"] + [
            "-v", f"{home}:{nix['home']}:U",  # ours on the host, the agent's inside
            "-v", f"{cwd}:{cwd}", "-w", cwd,
        ]
        args += token_args(conf, podman)
        if sys.stdin.isatty():
            args.append("-it")
        if debug:
            args.append("--log-level=debug")

        argv = [*podman, "run", "--rootfs", *args, root, *cmd]
        say(f"{cwd} :: {' '.join(cmd)}")
        if debug:
            print("+ " + " ".join(argv), file=sys.stderr)
        return subprocess.call(argv)
    finally:
        # anything the agent uid left behind is only ours inside the userns
        subprocess.call([*podman, "unshare", "rm", "-rf", root])


def parse_args(argv):
    flags, sep, cmd = argv, False, []
    if "--" in argv:
        i = argv.index("--")
        flags, sep, cmd = argv[:i], True, argv[i + 1:]
    if flags[:1] in (["-h"], ["--help"]):
        print(USAGE, end="")
        sys.exit(0)
    if "--new-ws" not in flags:
        return None, argv, []
    p = argparse.ArgumentParser(prog="gensokyo-agent", usage=USAGE, add_help=False, allow_abbrev=False)
    p.add_argument("--new-ws", action="store_true")
    p.add_argument("--name")
    p.add_argument("--flavor", default="nix")
    p.add_argument("-c", "--connection")
    p.add_argument("-s", "--secret", action="append", default=[])
    p.add_argument("--gpu", action="store_true")
    p.add_argument("--prompt")
    for flag in ("--git", "--cp", "--ro", "--rw", "--bind"):
        p.add_argument(flag, action="append", default=[])
    opts, passthrough = p.parse_known_args(flags)
    if sep and not cmd:
        die("nothing after --")
    return opts, cmd, passthrough


def parse_item(flag, spec):
    """[VOL=]SRC:DST[:DESC] -> (vol, src, dst, desc)"""
    vol = None
    if flag in ("--ro", "--rw") and "=" in spec.split(":")[0]:
        vol, spec = spec.split("=", 1)
    parts = spec.split(":", 2)
    if len(parts) < 2 or not parts[0] or not parts[1]:
        die(f"{flag} {spec}: expected SRC:DST[:DESC]")
    src = os.path.abspath(os.path.expanduser(parts[0]))
    dst = os.path.normpath(parts[1])
    if os.path.isabs(dst) or dst == "." or dst.split(os.sep)[0] == "..":
        die(f"{flag} {spec}: DST is relative to the workspace")
    if not os.path.exists(src):
        die(f"{flag} {spec}: no {src}")
    if flag != "--cp" and not os.path.isdir(src):
        die(f"{flag} {spec}: {src} is not a directory")
    if flag in ("--ro", "--rw"):
        vol = vol or re.sub(r"[^A-Za-z0-9_.-]+", "-", dst)
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", vol):
            die(f"{flag} {spec}: {vol} is not a volume name")
    return vol, src, dst, parts[2] if len(parts) > 2 else ""


def copy_in(src, work, dst):
    target = os.path.join(work, dst)
    if os.path.lexists(target):
        die(f"{dst} is in the workspace twice")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.isdir(src):
        shutil.copytree(src, target, symlinks=True)
    else:
        shutil.copy2(src, target)


def entrypoint(cmd, prompt):
    """The container's command: the agent on the first start, the same
    session again on any later one (podman start -ai)."""
    first = shlex.join(cmd + ([prompt] if prompt else []))
    again = f"exec {shlex.join(cmd)}"
    if os.path.basename(cmd[0]) == "claude":
        again = f"{shlex.join(cmd)} --continue && exit\n  {again}"
    return f"""#!/bin/sh
if [ -e "$HOME/.gensokyo-agent-started" ]; then
  {again}
fi
: > "$HOME/.gensokyo-agent-started"
exec {first}
"""


def claude_md(name, notes):
    lines = [
        f"# workspace {name}",
        "",
        "This directory was assembled for you and lives inside your sandbox.",
        "Its owner sees nothing in it but the commits they fetch.",
    ]
    for title, items in notes.items():
        if items:
            lines += ["", f"## {title}", ""] + [f"- {i}" for i in items]
    return "\n".join(lines) + "\n"


def git_out(conf, repo, *args):
    r = subprocess.run([conf["git"], "-C", repo, *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def parse_git(conf, spec, name):
    """[@]PATH[:BASE[:[NEW]]] -> the repository, what to clone and the branch to be on"""
    full = spec.startswith("@")
    parts = spec.removeprefix("@").split(":")
    if len(parts) > 3 or not parts[0]:
        die(f"--git {spec}: expected [@]PATH[:BASE[:NEW]]")
    top = git_out(conf, os.path.expanduser(parts[0]), "rev-parse", "--show-toplevel") if os.path.isdir(os.path.expanduser(parts[0])) else None
    if top is None:
        die(f"--git {spec}: {parts[0]} is not a git checkout")
    base = parts[1] if len(parts) > 1 and parts[1] else git_out(conf, top, "symbolic-ref", "-q", "--short", "HEAD")
    if base is None:
        die(f"--git {spec}: HEAD is detached, name the branch to start from")
    ref = git_out(conf, top, "rev-parse", "-q", "--verify", "--symbolic-full-name", base)
    if not ref:
        die(f"--git {spec}: {base} is not a branch or tag of {top}")
    if len(parts) == 3:
        branch = parts[2] or name
    elif ref.startswith("refs/heads/"):
        branch = base
    else:
        die(f"--git {spec}: {base} is not a local branch, name a new one to work on")
    if name in (git_out(conf, top, "remote") or "").split():
        die(f"--git {spec}: {top} already has a remote {name}")
    return {"top": top, "repo": os.path.basename(top), "full": full, "base": base, "ref": ref, "branch": branch}


def clone_in(conf, g, work):
    """The owner's branch arrives as owner/BASE and is all there is: no
    remote to push to, and one commit of history unless asked for all."""
    dst = os.path.join(work, "src", g["repo"])
    if os.path.lexists(dst):
        die(f"src/{g['repo']} is in the workspace twice")
    os.makedirs(dst)
    owner = f"refs/remotes/owner/{g['base']}"
    for args in (
        ["init", "-q"],
        ["fetch", "-q", *([] if g["full"] else ["--depth", "1"]), "file://" + g["top"], f"+{g['ref']}:{owner}"],
        ["checkout", "-q", "--no-track", "-B", g["branch"], owner],
    ):
        if subprocess.run([conf["git"], "-C", dst, *args]).returncode != 0:
            die(f"--git: git {args[0]} failed for {g['top']}")


def add_remote(conf, g, name, podman, workdir):
    """The remote is podman itself, so it is wherever the container is."""
    def esc(word):
        return word.replace("%", "%%").replace(" ", "% ")
    exe = os.environ.get("GENSOKYO_AGENT_PODMAN", "podman")
    url = "ext::" + " ".join(map(esc, [exe, *podman[1:], "exec", "-i", name])) + " %S " + esc(f"{workdir}/src/{g['repo']}")
    for args in (
        ["remote", "add", name, url],
        # git push NAME master: the agent sees it as owner/master
        ["config", f"remote.{name}.push", "refs/heads/*:refs/remotes/owner/*"],
        ["config", "protocol.ext.allow", "user"],
    ):
        if subprocess.run([conf["git"], "-C", g["top"], *args]).returncode != 0:
            die(f"--git: could not add the remote {name} to {g['top']}")


def new_workspace(conf, opts, cmd, passthrough):
    podman = [conf["podman"]] + (["-c", opts.connection] if opts.connection else [])
    debug = os.environ.get("DEBUG", "0") == "1"

    def call(argv, **kw):
        if debug:
            print("+ " + shlex.join(argv), file=sys.stderr)
        return subprocess.run(argv, **kw).returncode

    def taken(n):
        return call([*podman, "container", "exists", n]) == 0

    flavor = conf["flavors"].get(opts.flavor) or die(f"--flavor is one of: {' '.join(conf['flavors'])}")
    if opts.gpu and flavor["gpuArgs"] is None:
        die(f"--gpu: not in the {opts.flavor} flavor")
    if opts.bind and opts.connection:
        die("--bind: a path of this machine cannot be bound on another")

    name = opts.name
    if name is None:
        while name is None or taken(name):
            name = f"{random.choice(ADJECTIVES)}_{random.choice(NOUNS)}"
    elif not re.fullmatch(NAME_RE, name):
        die(f"--name {name}: lowercase letters, digits, _ . - only")
    elif taken(name):
        die(f"--name {name}: there is a container of that name")
    items = [(flag, *parse_item(flag, spec))
             for flag in ("--cp", "--ro", "--rw", "--bind") for spec in getattr(opts, flag[2:])]
    repos = [parse_git(conf, spec, name) for spec in opts.git]
    cmd = cmd or os.environ.get("AGENT_CMD", conf["defaultCmd"]).split()

    # the workspace has one path, here while it is assembled and in the
    # container afterwards. not under /tmp, that is a tmpfs in the sandbox
    base = os.environ.get("GENSOKYO_AGENT_TMPDIR", "/var/tmp/gensokyo-agent")
    workdir = os.path.join(base, name)
    ctx = workdir + ".ctx"
    work = os.path.join(ctx, "work")
    if not os.path.isdir(base):
        os.makedirs(base)
        os.chmod(base, 0o1777)
    os.mkdir(ctx)
    try:
        os.mkdir(work)
        root = os.path.join(ctx, "root")
        if flavor["root"]:
            copy_writable(flavor["root"], root)
            # COPY --chown makes the home the agent's only if it makes it
            shutil.rmtree(root + flavor["home"], ignore_errors=True)
        os.makedirs(os.path.join(root, ".gensokyo-agent"), exist_ok=True)
        with open(os.path.join(root, ".gensokyo-agent", "entrypoint"), "w") as f:
            f.write(entrypoint(cmd, opts.prompt))
            os.fchmod(f.fileno(), 0o755)
        write_home(os.path.join(ctx, "home"), workdir)

        mounts = []
        notes = {"repositories": [], "files": []}
        for g in repos:
            clone_in(conf, g, work)
            notes["repositories"].append(
                f"`src/{g['repo']}`, on `{g['branch']}`, started from the owner's `{g['base']}`"
                f"{'' if g['full'] else ' with one commit of history'}. Commit here; there is nowhere"
                f" to push, the owner fetches. What they send arrives as `owner/<branch>`")
        for flag, vol, src, dst, desc in items:
            inside = os.path.join(workdir, dst)
            desc = f": {desc}" if desc else ""
            if flag == "--cp":
                copy_in(src, work, dst)
                notes["files"].append(f"`{dst}`, a copy{desc}")
            elif flag == "--bind":
                mounts += ["-v", f"{src}:{inside}"]
                notes["files"].append(f"`{dst}`, the owner's own directory, changes there are real{desc}")
            else:
                # a new volume takes what the image has at its mount point
                if call([*podman, "volume", "exists", vol]) == 0:
                    say(f"volume {vol} exists, used as it is")
                    os.makedirs(os.path.join(work, dst))
                else:
                    copy_in(src, work, dst)
                ro = flag == "--ro"
                mounts += ["-v", f"{vol}:{inside}" + (":ro" if ro else "")]
                notes["files"].append(
                    f"`{dst}`, a {'read-only ' if ro else ''}volume that other workspaces may share"
                    f"{'' if ro else ' and that outlives this one'}{desc}")
        with open(os.path.join(work, "CLAUDE.md"), "a") as f:
            f.write(claude_md(name, notes))

        user = flavor["user"]
        containerfile = flavor["containerfile"] + "".join([
            "COPY root/ /\n",
            f"COPY --chown={user} home/ {flavor['home']}/\n",
            f"COPY --chown={user} work/ {workdir}/\n",
        ])
        image = f"localhost/gensokyo-agent/{name}"
        with open(os.path.join(ctx, "Containerfile"), "w") as f:
            f.write(containerfile)
        if call([*podman, "build", "-t", image, "-f", os.path.join(ctx, "Containerfile"), ctx]) != 0:
            die("podman build failed")
    finally:
        remove_tree(ctx)

    for g in repos:
        add_remote(conf, g, name, podman, workdir)

    args = ["--name", name, "--label", f"gensokyo-agent={name}", "--log-driver", "none", "-w", workdir]
    args += flavor["runArgs"]
    if opts.gpu:
        args += flavor["gpuArgs"]
    args += token_args(conf, podman)
    for spec in opts.secret:
        args += ["--secret", spec]
    args += mounts
    if sys.stdin.isatty():
        args.append("-it")
    argv = [*podman, "run", *args, *passthrough, image, "/.gensokyo-agent/entrypoint"]

    pm = shlex.join(["podman"] + podman[1:])
    say(f"workspace {name} ({opts.flavor}) at {workdir}")
    say(f"  leave with ctrl-p ctrl-q, return with: {pm} attach {name}")
    say(f"  once it has stopped: {pm} start -ai {name}")
    for g in repos:
        say(f"  its work, while it runs: git -C {g['top']} fetch {name}")
    say(f"  remove: {pm} rm {name} && {pm} rmi {image}")
    if debug:
        print("+ " + shlex.join(argv), file=sys.stderr)
    sys.stdout.flush()
    sys.stderr.flush()
    os.execvp(argv[0], argv)


def main():
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda *_: sys.exit(1))
    opts, cmd, passthrough = parse_args(sys.argv[1:])
    conf = load_conf()
    if opts is None:
        sys.exit(run_here(conf, cmd))
    new_workspace(conf, opts, cmd, passthrough)


if __name__ == "__main__":
    main()
