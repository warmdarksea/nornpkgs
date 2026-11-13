import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile


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


def run_here(conf, cmd):
    """One command in a throwaway sandbox, the current directory mounted."""
    podman = [conf["podman"]]
    debug = os.environ.get("DEBUG", "0") == "1"
    cmd = cmd or os.environ.get("AGENT_CMD", conf["defaultCmd"]).split()
    cwd = os.getcwd()

    # rootless podman can't write into a root-owned store path (unmapped uid,
    # no DAC override in the userns), so stage the skeleton somewhere we own
    base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "gensokyo-agent")
    os.makedirs(base, exist_ok=True)
    root = tempfile.mkdtemp(prefix="root.", dir=base)
    try:
        copy_writable(conf["rootfs"], root)
        os.chmod(root, 0o755)  # mkdtemp gives 0700; / must be traversable by the agent uid
        home = root + conf["home"]
        write_home(home, cwd)

        args = conf["runArgs"] + [
            "-v", f"{home}:{conf['home']}:U",  # ours on the host, the agent's inside
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


def main():
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda *_: sys.exit(1))
    sys.exit(run_here(load_conf(), sys.argv[1:]))


main()
