import argparse
import io
import json
import os
import random
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse

USAGE = """\
gensokyo-agent [FLAG...] [-- CMD...]     CMD (default: claude) in a workspace: a
                                         directory assembled from local files,
                                         built into an image and run as a
                                         container that stays
gensokyo-agent --legacy [CMD...]         CMD in a throwaway sandbox on the
                                         current directory
gensokyo-agent --history [-c CONN]...    the conversations of every workspace,
                                         here and on every connection (or those
                                         of -c), and yours: when, where, how
                                         long, and what you said first
gensokyo-agent --copy-history [-c CONN]... [DIR]
                                         those gathered in DIR (default:
                                         ~/.local/share/gensokyo-agent/history)
                                         as CONN/NAME/projects; nothing there
                                         is ever removed
  --name NAME                container and image name (default: generated)
  -c, --connection NAME       podman connection to build and run on
  -s, --secret SPEC           as podman run --secret
  --gpu                       the nvidia devices and CUDA
  --vm, --no-vm               /dev/kvm, on by default
  -d, --device SPEC           as podman run --device. the agent has your
                              groups then, to use it with: /dev/kvm too
  --from [CONN/]NAME          carry on from the workspace NAME, on the host of
                              the podman connection CONN (default: here),
                              stopped first: its claude home (the
                              conversation, its memory), its path, so claude
                              --continue picks up where it was, its closure,
                              and its name, unless --name. on its own host
                              under its own name it is replaced: removed once
                              the new one is created. on another, it is left
                              as it is
  --copy, --no-copy           with --from, bring its files as they are,
                              uncommitted changes and all: on by default.
                              not what it mounts (volumes, --bind), which
                              take their flags again
  --closure FLAKE[#NAME]      build the flake's agentClosures.<system>.NAME
                              (default: default) here, and give the agent
                              its packages and MCP servers. for -c, copied
                              to its host (nix copy: be a trusted user there)
  --git [@]PATH[:BASE[:[NEW]]]
                              clone the checkout at PATH into src/, one
                              commit deep (@: all of it), and give PATH a
                              remote NAME to fetch the work from. BASE: the
                              branch to be on, default the current one.
                              NEW: a branch to start from it, default
                              master: the owner fetches NAME/master
  --git-add-remote PATH       only the remote: give the checkout at PATH a
                              remote NAME to the src/ checkout the workspace
                              has already, one --from brought. a remote NAME
                              that is there already is not replaced
  --cp SRC:DST[:DESC]         copy SRC to DST in the workspace
  --ro [VOL=]SRC:DST[:DESC]   a volume seeded from SRC at DST, read-only;
  --rw [VOL=]SRC:DST[:DESC]   or writable. volumes outlive the workspace,
                              and one that exists is used as it is
  --bind SRC:DST[:DESC]       SRC itself at DST; local only
  --prompt TEXT               what the agent starts on
  --model MODEL               the agent's model, as it names them. claude:
                              fable, opus, sonnet, haiku, opusplan, or a
                              full model name; [1m] after it for the long
                              context. default: claude-opus-5-5[1m]. agy:
                              agy models lists them. codex: -m
  --effort LEVEL              claude, agy: low, medium, high, xhigh, max.
                              codex: its model_reasoning_effort. any other
                              agent takes either after --, its own way
  -p, --publish SPEC          as podman run -p, but a PORT alone is
                              PORT:PORT, the same port on every interface
                              here (podman's would be a random one)
  -L SPEC                     as ssh -L, to the host of -c; the tunnel stays
                              up after this command returns
  -sp PORT                    both for one port: localhost:PORT here is
                              PORT in the workspace, wherever it runs
  anything else               goes to podman run
DST is relative to the workspace; DESC ends up in its CLAUDE.md.

examples:
  gensokyo-agent --git .::
      claude in a workspace, on this checkout's branch cloned to master
      there. the checkout gets a remote of the workspace's name: git fetch
      NAME, which starts the workspace for as long as it takes if it had
      stopped, brings that as NAME/master
  gensokyo-agent --git ~/src/nornpkgs:master:fix-build --prompt "make ci_check pass"
      the branch to start from and the one to make, and what to do there
  gensokyo-agent -c library --gpu --git @.:: --ro ~/datasets/foo:data/foo:"the training set"
      on the host of the podman connection library, with its GPU, the whole
      history, and a directory of this machine as a read-only volume there
  gensokyo-agent -c library -sp 8800 --git .::
      what the agent serves on 0.0.0.0:8800 answers on localhost:8800 here
  gensokyo-agent --closure .#lean --git .::
      with the packages and MCP servers of this flake's closure lean, made
      with nornpkgs.lib.mkAgentClosure
  gensokyo-agent --from jolly_swartz --closure .#lean
      jolly_swartz again, files and all, with another closure: the old
      container goes once the new one is there
  gensokyo-agent -c library --from hell/jolly_swartz --git-add-remote .
      jolly_swartz of the connection hell, copied to library with its
      closure; this checkout's remote jolly_swartz points to the copy
      (git remote remove jolly_swartz first, if it was the old one's)
  gensokyo-agent --from jolly_swartz --no-copy --git .:jolly_swartz:
      its conversation only, on the branch fetched from it (git fetch
      jolly_swartz && git branch jolly_swartz jolly_swartz/master)
  gensokyo-agent -s openai-api-key,type=env,target=OPENAI_API_KEY -- codex
      another agent, and a secret of its own
  gensokyo-agent --git .:: -- agy --dangerously-skip-permissions
      google's agent, with the podman secret gemini-api-key if there is
      one (and not claude's token), or its google login, once per workspace
  gensokyo-agent --legacy
      claude on the current directory, gone when it exits

afterwards, with podman (and -c where the workspace is elsewhere):
  podman attach NAME            back in; leave with ctrl-p ctrl-q
  podman start -ai NAME         once it has stopped: the same session again
  podman exec -it NAME bash     a shell next to the agent
  podman rm NAME && podman rmi gensokyo-agent/NAME
"""

# the container names of moby's legacy names-generator.go, ported: two
# lists and the one exception. Apache-2.0, from
# https://github.com/moby/moby/blob/f8b81d90660723258fd2a5692bb61d9911ac6bc4/internal/namesgenerator/legacy/names-generator.go
ADJECTIVES = """admiring adoring affectionate agitated amazing angry awesome beautiful
blissful bold boring brave busy charming clever compassionate competent
condescending confident cool cranky crazy dazzling determined distracted
dreamy eager ecstatic elastic elated elegant eloquent epic exciting fervent
festive flamboyant focused friendly frosty funny gallant gifted goofy
gracious great happy hardcore heuristic hopeful hungry infallible inspiring
intelligent interesting jolly jovial keen kind laughing loving lucid
magical modest musing mystifying naughty nervous nice nifty nostalgic
objective optimistic peaceful pedantic pensive practical priceless quirky
quizzical recursing relaxed reverent romantic sad serene sharp silly sleepy
stoic strange stupefied suspicious sweet tender thirsty trusting unruffled
upbeat vibrant vigilant vigorous wizardly wonderful xenodochial youthful
zealous ze""".split()
# notable scientists and hackers; the file has a line on each
SURNAMES = """agnesi albattani allen almeida antonelli archimedes ardinghelli aryabhata
austin babbage banach banzai bardeen bartik bassi beaver bell benz bhabha
bhaskara black blackburn blackwell bohr booth borg bose bouman boyd
brahmagupta brattain brown buck burnell cannon carson cartwright carver
cerf chandrasekhar chaplygin chatelet chatterjee chaum chebyshev clarke
cohen colden cori cray curie curran darwin davinci dewdney dhawan diffie
dijkstra dirac driscoll dubinsky easley edison einstein elbakyan elgamal
elion ellis engelbart euclid euler faraday feistel fermat fermi feynman
franklin gagarin galileo galois ganguly gates gauss germain goldberg
goldstine goldwasser golick goodall gould greider grothendieck haibt
hamilton haslett hawking heisenberg hellman hermann herschel hertz
heyrovsky hodgkin hofstadter hoover hopper hugle hypatia ishizaka jackson
jang jemison jennings jepsen johnson joliot jones kalam kapitsa kare
keldysh keller kepler khayyam khorana kilby kirch knuth kowalevski lalande
lamarr lamport leakey leavitt lederberg lehmann lewin lichterman liskov
lovelace lumiere mahavira margulis matsumoto maxwell mayer mccarthy
mcclintock mclaren mclean mcnulty meitner mendel mendeleev meninsky merkle
mestorf mirzakhani montalcini moore morse moser murdock napier nash neumann
newton nightingale nobel noether northcutt noyce panini pare pascal pasteur
payne perlman pike poincare poitras proskuriakova ptolemy raman ramanujan
rhodes ride ritchie robinson roentgen rosalind rubin saha sammet sanderson
satoshi shamir shannon shaw shirley shockley shtern sinoussi snyder solomon
spence stonebraker sutherland swanson swartz swirles taussig tesla tharp
thompson torvalds tu turing varahamihira vaughan villani visvesvaraya
volhard wescoff wilbur wiles williams williamson wilson wing wozniak wright
wu yalow yonath zhukovsky""".split()


def random_name():
    """adjective_surname, as docker names a container."""
    while True:
        name = f"{random.choice(ADJECTIVES)}_{random.choice(SURNAMES)}"
        if name != "boring_wozniak":  # Steve Wozniak is not boring
            return name


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


def decide(decision):
    return f"""echo '{{"hookSpecificOutput": {{"hookEventName": "PreToolUse", "permissionDecision": "{decision}"}}}}'"""


# the env scrub puts claude in its default permission mode, whatever the
# command line says, and an allow rule names a tool or a server: none
# covers what claude does outside its directory, or a server it has not
# met. a hook may allow a call all the same, so one allows all of them.
# it cannot allow what claude asks about in any mode but bypass: an edit
# of .git, .claude, .mcp.json and the like. the claude.ai connectors, the
# owner's accounts elsewhere, are not loaded (ENABLE_CLAUDEAI_MCP_SERVERS),
# and refused should one be all the same
HOOKS = [
    {"matcher": "^(?!mcp__claude_ai_)", "hooks": [{"type": "command", "command": decide("allow")}]},
    {"matcher": "^mcp__claude_ai_", "hooks": [{"type": "command", "command": decide("deny")}]},
]


# claude's model unless --model says otherwise, with the long context
MODEL = "claude-opus-5-5[1m]"


def write_home(home, workdir):
    """The sandbox has no home of its own to remember the first-run dialogs."""
    os.makedirs(os.path.join(home, ".claude"), exist_ok=True)
    with open(os.path.join(home, ".claude.json"), "w") as f:
        json.dump({
            "hasCompletedOnboarding": True,
            "theme": "auto",
            # the notices of auto mode: what it is, and the offer to make it the default
            "hasSeenAutoModeEntryWarning": True,
            "hasSeenAutoDefaultNotice": True,
            "hasSeenAutoDefaultNudge": True,
            "projects": {workdir: {"hasTrustDialogAccepted": True}},
        }, f)
    with open(os.path.join(home, ".claude", "settings.json"), "w") as f:
        json.dump({
            "model": MODEL,
            # auto mode is the one to start in, and its opt-in dialog has been
            # accepted; claude forgets the latter when the default is another mode
            "permissions": {"defaultMode": "auto"},
            "skipAutoPermissionPrompt": True,
            "skipDangerousModePermissionPrompt": True,
            # the .mcp.json of the directory claude starts in is not one to ask about
            "enableAllProjectMcpServers": True,
            "hooks": {"PreToolUse": HOOKS},
        }, f)


def agent_conf(conf, cmd):
    """What the wrapper knows of the agent cmd runs (agents in lib/agent.nix)."""
    return conf.get("agents", {}).get(os.path.basename(cmd[0]), {})


# the closure's MCP servers, as claude has them, for an agent that reads them
# from a file of its own, in its format: the ${VAR} and ${VAR:-DEFAULT} claude
# fills in from its environment filled in first, from the workspace's
MCP_EXPAND = """.mcpServers |= map_values(walk(if type == "string"
  then gsub("\\\\$\\\\{(?<n>[A-Za-z_][A-Za-z0-9_]*)(?<o>:-(?<d>[^}]*))?\\\\}";
            if .o != null and ($ENV[.n] // "") == "" then .d else $ENV[.n] // "" end)
  else . end))"""
MCP_FORMATS = {
    # agy's mcp_config.json: a server by url one by serverUrl
    "agy": """.mcpServers |= map_values(
  if .url then {serverUrl: .url} + (if .headers then {headers} else {} end) else del(.type) end)""",
    # codex's config.toml, a table each; JSON's strings and arrays are TOML's
    "codex": """.mcpServers | to_entries[]
| "[mcp_servers.\\(.key | tojson)]",
  (.value | if .url then {url, http_headers: .headers} else {command, args, env} end
   | to_entries[] | select(.value != null)
   | "\\(.key) = \\(if (.value | type) == "object"
                  then "{ " + (.value | to_entries | map("\\(.key | tojson) = \\(.value | tojson)") | join(", ")) + " }"
                  else .value | tojson end)"),
  "" """,
}


def token_args(conf, podman, cmd, home):
    """The login of the agent cmd runs: claude's token, or that of an agent
    with its own, and what that one needs in the home."""
    token = agent_conf(conf, cmd).get("token", conf["token"])
    if subprocess.call([*podman, "secret", "exists", token["secret"]], stdout=subprocess.DEVNULL) != 0:
        why = token.get("missing", "the agent starts logged out; create it from `claude setup-token`")
        say(f"no podman secret {token['secret']} here, {why} with: {' '.join(podman)} secret create {token['secret']} -")
        return []
    for path, content in token.get("home", {}).items():
        os.makedirs(os.path.dirname(os.path.join(home, path)), exist_ok=True)
        with open(os.path.join(home, path), "w") as f:
            json.dump(content, f)
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

    # rootless podman can't write into a root-owned store path (unmapped uid,
    # no DAC override in the userns), so stage the skeleton somewhere we own
    base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "gensokyo-agent")
    os.makedirs(base, exist_ok=True)
    root = tempfile.mkdtemp(prefix="root.", dir=base)
    try:
        copy_writable(conf["root"], root)
        os.chmod(root, 0o755)  # mkdtemp gives 0700; / must be traversable by the agent uid
        home = root + conf["home"]
        write_home(home, cwd)

        args = conf["hereArgs"] + [
            "-v", f"{home}:{conf['home']}:U",  # ours on the host, the agent's inside
            "-v", f"{cwd}:{cwd}", "-w", cwd,
        ]
        args += token_args(conf, podman, cmd, home)
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
    if argv[:1] == ["--legacy"]:
        return None, argv[1:], []
    p = argparse.ArgumentParser(prog="gensokyo-agent", usage=USAGE, add_help=False, allow_abbrev=False)
    p.add_argument("--name")
    p.add_argument("-c", "--connection")
    p.add_argument("-s", "--secret", action="append", default=[])
    p.add_argument("--gpu", action="store_true")
    p.add_argument("--vm", action=argparse.BooleanOptionalAction)
    p.add_argument("-d", "--device", action="append", default=[])
    p.add_argument("--from", dest="from_")
    p.add_argument("--copy", action=argparse.BooleanOptionalAction)
    p.add_argument("--closure")
    p.add_argument("--git-add-remote", action="append", default=[])
    p.add_argument("--prompt")
    p.add_argument("--model")
    p.add_argument("--effort")
    p.add_argument("-p", "--publish", action="append", default=[])
    p.add_argument("-L", dest="tunnel", action="append", default=[])
    p.add_argument("-sp", dest="port", action="append", default=[])
    for flag in ("--git", "--cp", "--ro", "--rw", "--bind"):
        p.add_argument(flag, action="append", default=[])
    opts, passthrough = p.parse_known_args(flags)
    if sep and not cmd:
        die("nothing after --")
    if passthrough and not passthrough[0].startswith("-"):
        die(f"{passthrough[0]}: a command goes after --, or after --legacy for the sandbox on the current directory")
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


def entrypoint(cmd, prompt, resume=False, setup=""):
    """The container's command: the agent on the first start, the same
    session again on any later one (podman start -ai); with resume, on
    the first too, that of the workspace it carries on from. setup runs
    before the first."""
    claude = os.path.basename(cmd[0]) == "claude"
    run = shlex.join(cmd)
    # claude's list flags (--allowedTools and the like) take every word up
    # to the next flag, a prompt that follows them included
    first = run + (" --continue" if claude and resume else "")
    first += ((" --" if claude else "") + " " + shlex.quote(prompt) if prompt else "")
    again = f"exec {run}"
    if claude:
        again = f"{run} --continue && exit\n  {again}"
    return f"""#!/bin/sh
if [ -e "$HOME/.gensokyo-agent-started" ]; then
  {again}
fi
: > "$HOME/.gensokyo-agent-started"
{setup}exec {first}
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


def parse_git(conf, spec):
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
        branch = parts[2] or "master"
    elif ref.startswith("refs/heads/"):
        branch = base
    else:
        die(f"--git {spec}: {base} is not a local branch, name a new one to work on")
    return {"top": top, "repo": os.path.basename(top), "full": full, "base": base, "ref": ref, "branch": branch}


def parse_add_remote(conf, spec):
    """PATH -> the checkout whose remote --git-add-remote adds, nothing cloned"""
    path = os.path.expanduser(spec)
    top = git_out(conf, path, "rev-parse", "--show-toplevel") if os.path.isdir(path) else None
    if top is None:
        die(f"--git-add-remote {spec}: not a git checkout")
    return {"top": top, "repo": os.path.basename(top), "add_only": True}


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


# the remote's command: git-upload-pack or git-receive-pack ($2) in the
# container $1, which is started for it when it had stopped, and stopped again
SERVE = """n=$1 s=$2 d=$3; shift 3
up=$("$@" container inspect -f {{.State.Running}} "$n") || exit
[ "$up" = true ] || "$@" start "$n" >/dev/null || exit
"$@" exec -i "$n" "$s" "$d"; r=$?
[ "$up" = true ] || "$@" stop "$n" >/dev/null
exit $r"""


def remote_url(g, name, podman, workdir):
    """The remote is podman itself, so it is wherever the container is."""
    def esc(word):
        return word.replace("%", "%%").replace(" ", "% ")
    exe = os.environ.get("GENSOKYO_AGENT_PODMAN", "podman")
    script = "; ".join(SERVE.splitlines())
    return "ext::" + " ".join([*map(esc, ["sh", "-c", script, "sh", name]), "%S", *map(esc, [f"{workdir}/src/{g['repo']}", exe, *podman[1:]])])


def check_remote(conf, g, name, url):
    """A remote NAME there already is never replaced; one that is the same
    (the workspace replaced under its own name, on its own host) is kept."""
    if name not in (git_out(conf, g["top"], "remote") or "").split():
        return False
    if git_out(conf, g["top"], "config", f"remote.{name}.url") != url:
        flag = "--git-add-remote" if g.get("add_only") else "--git"
        die(f"{flag}: {g['top']} already has a remote {name}, elsewhere; git -C {shlex.quote(g['top'])} remote remove {name} first")
    return True


def add_remote(conf, g, name, url, exists):
    for args in (
        *([] if exists else [["remote", "add", name, url]]),
        # git push NAME master: the agent sees it as owner/master
        ["config", f"remote.{name}.push", "refs/heads/*:refs/remotes/owner/*"],
        ["config", "protocol.ext.allow", "user"],
    ):
        if subprocess.run([conf["git"], "-C", g["top"], *args]).returncode != 0:
            die(f"--git: could not add the remote {name} to {g['top']}")


def ssh_target(conf, connection, flag="-L"):
    """What ssh needs to reach the host of a podman connection."""
    out = subprocess.run([conf["podman"], "system", "connection", "ls", "--format", "json"],
                         stdout=subprocess.PIPE, text=True).stdout
    for c in json.loads(out or "[]"):
        if c["Name"] == connection:
            uri = urllib.parse.urlsplit(c["URI"])
            if uri.scheme != "ssh":
                die(f"{flag}: the connection {connection} is not over ssh")
            return [
                *(["-p", str(uri.port)] if uri.port else []),
                *(["-i", c["Identity"]] if c.get("Identity") else []),
                (f"{uri.username}@" if uri.username else "") + uri.hostname,
            ]
    die(f"{flag}: no podman connection {connection}")


def state_dir():
    return os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "gensokyo-agent")


def closure_root(name, taken):
    """Where the closure of the workspace NAME here is rooted, for as long as
    it is there; the roots of workspaces that are gone go."""
    roots = state_dir()
    # an hour, as one may be assembled still
    for old in os.listdir(roots) if os.path.isdir(roots) else []:
        path = os.path.join(roots, old)
        if time.time() - os.lstat(path).st_mtime > 3600 and not taken(old):
            shutil.rmtree(path, ignore_errors=True)
    os.makedirs(os.path.join(roots, name), exist_ok=True)
    return os.path.join(roots, name, "closure")


def closure_servers(closure):
    """The names of the MCP servers of a closure of mkAgentClosure, or None."""
    try:
        with open(os.path.join(closure, "share", "gensokyo-agent", "mcp.json")) as f:
            servers = json.load(f)["mcpServers"]
        if not isinstance(servers, dict):
            raise TypeError
    except (OSError, ValueError, LookupError, TypeError):
        return None
    return list(servers)


def build_closure(conf, spec, link, call):
    """Build what --closure names here, rooted at LINK; its store path and
    its MCP servers."""
    ref, _, attr = spec.partition("#")
    if os.path.isdir(os.path.expanduser(ref or ".")):
        ref = os.path.abspath(os.path.expanduser(ref or "."))
    attr = f"agentClosures.{conf['system']}.{attr or 'default'}"
    if call([conf["nix"], "--extra-experimental-features", "nix-command flakes",
             "build", "--out-link", link, f"{ref}#{attr}"]) != 0:
        shutil.rmtree(os.path.dirname(link), ignore_errors=True)
        die(f"--closure {spec}: nix build {ref}#{attr} failed")
    closure = os.path.realpath(link)
    servers = closure_servers(closure)
    if servers is None:
        shutil.rmtree(os.path.dirname(link), ignore_errors=True)
        die(f"--closure {spec}: no share/gensokyo-agent/mcp.json in {closure}, not a closure of nornpkgs.lib.mkAgentClosure")
    return closure, servers


def copy_closure(conf, closure, src, dst, call):
    """nix copy a closure from the host of the connection SRC to that of DST
    (None: here), by way of here. a path built here is signed by no one, so
    it takes a trusted user at the other end"""
    for flag, conn in (("--from", src), ("--to", dst)):
        if conn is None:
            continue
        *sshopts, target = ssh_target(conf, conn, "--closure")
        env = dict(os.environ, NIX_SSHOPTS=" ".join(sshopts))
        if call([conf["nix"], "--extra-experimental-features", "nix-command", "copy", "--no-check-sigs",
                 flag, f"ssh-ng://{target}", closure], env=env) != 0:
            die(f"--closure: nix copy {flag} {conn} of {closure} failed")


# rooting a closure on the host of a connection, as closure_root here: $1 the
# workspace, $2 the closure. podman and nix-store are those of the PATH there
ROOT = """d=${XDG_STATE_HOME:-$HOME/.local/state}/gensokyo-agent
mkdir -p "$d"
for o in $(find "$d" -mindepth 1 -maxdepth 1 -mmin +60); do podman container exists "${o##*/}" || rm -rf "$o"; done
mkdir -p "$d/$1" && nix-store --realise "$2" --add-root "$d/$1/closure" >/dev/null"""


def root_closure(conf, closure, name, connection, call, taken):
    """Root a closure that is in the store of the workspace's host already."""
    if connection is None:
        link = closure_root(name, taken)
        if call([conf["nix"], "--extra-experimental-features", "nix-command",
                 "build", "--out-link", link, closure]) != 0:
            die(f"--closure: could not root {closure}")
        return
    *sshopts, target = ssh_target(conf, connection, "--closure")
    if call([conf["ssh"], *sshopts, target, shlex.join(["sh", "-c", ROOT, "sh", name, closure])]) != 0:
        die(f"--closure: could not root {closure} on the host of {connection}")


LABEL = "gensokyo-agent.opts"


def inspect_workspace(conf, podman, spec):
    """The workspace OLD, a container of gensokyo-agent: its path, its
    state, and what the label of this wrapper says of how it was made."""
    conn, _, old = spec.rpartition("/")
    podman = podman[:1] + (["-c", conn] if conn else [])
    r = subprocess.run([*podman, "container", "inspect", "--format", "json", old],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        (c,) = json.loads(r.stdout) if r.returncode == 0 else [None]
        labels = c["Config"].get("Labels") or {}
        workdir = c["Config"]["WorkingDir"]
        if labels.get("gensokyo-agent") is None or not os.path.isabs(workdir):
            raise LookupError
    except (ValueError, LookupError, TypeError):
        die(f"--from {spec}: no workspace of that name {'on ' + conn if conn else 'here'}")
    try:
        record = json.loads(labels.get(LABEL) or "null")
    except ValueError:
        record = None
    if not isinstance(record, dict):
        record = None
    mounts = [m for m in c.get("Mounts") or [] if isinstance(m, dict)]
    if record is not None:
        closure, servers = record.get("closure"), record.get("servers") or []
    else:
        # made before the label: the closure is the source of its bind
        default = conf["closure"]["default"]
        closure = next((m.get("Source") for m in mounts if m.get("Destination") == conf["closure"]["at"]), None)
        if closure in (default, os.path.realpath(default)) or (closure or "").startswith(os.path.dirname(default) + "/"):
            closure = None
        servers = (closure_servers(closure) if closure and not conn else None) or []
    return {
        "name": old, "connection": conn or None, "podman": podman, "workdir": workdir,
        "running": bool((c.get("State") or {}).get("Running")), "image": c.get("Image"),
        "mounts": [m.get("Destination") for m in mounts if m.get("Destination")],
        "closure": closure, "servers": servers,
    }


def carried_files(old, work, workdir):
    """What podman cp brought of OLD's workspace, less what it mounted there
    (volumes and binds, which come by their flags or not at all), and less
    its CLAUDE.md of this wrapper's, written anew."""
    for dst in old["mounts"]:
        rel = os.path.relpath(dst, workdir)
        path = os.path.join(work, rel)
        if rel == "." or rel.split(os.sep)[0] == ".." or not os.path.lexists(path):
            continue
        if os.path.isdir(path) and not os.path.islink(path):
            remove_tree(path)
        else:
            os.unlink(path)
    md = os.path.join(work, "CLAUDE.md")
    if os.path.isfile(md) and not os.path.islink(md):
        with open(md) as f:
            text = f.read()
        # what the owner's --cp put before the wrapper's part stays
        m = re.search(rf"(?m)^# workspace {re.escape(old['name'])}\n", text)
        if m:
            with open(md, "w") as f:
                f.write(text[:m.start()])


def new_workspace(conf, opts, cmd, passthrough):
    podman = [conf["podman"]] + (["-c", opts.connection] if opts.connection else [])
    debug = os.environ.get("DEBUG", "0") == "1"

    def call(argv, **kw):
        if debug:
            print("+ " + shlex.join(argv), file=sys.stderr)
        return subprocess.run(argv, **kw).returncode

    def taken(n):
        return call([*podman, "container", "exists", n]) == 0

    if opts.vm is None:
        opts.vm = True
    if opts.bind and opts.connection:
        die("--bind: a path of this machine cannot be bound on another")
    if opts.copy is not None and not opts.from_:
        die("--copy: of the workspace --from names")
    # a port alone is the same port on the host, not podman's random one
    opts.publish = [re.sub(r"^(\d+)(/\w+)?$", r"\1:\1\2", spec) for spec in opts.publish]
    for port in opts.port:
        if not port.isdigit():
            die(f"-sp {port}: a port number")
        opts.publish.append(f"127.0.0.1:{port}:{port}")
        if opts.connection:
            opts.tunnel.append(f"{port}:127.0.0.1:{port}")
    if opts.tunnel and not opts.connection:
        die("-L: without -c the workspace is on this machine, -p is all it takes")
    # the path the conversation knows, and that of its history in the home
    old = inspect_workspace(conf, podman, opts.from_) if opts.from_ else None
    copy = old is not None and opts.copy is not False
    target = ssh_target(conf, opts.connection) if opts.tunnel else None

    # one carried on from keeps its name; on its own host it is replaced
    name = opts.name or (old and old["name"])
    replace = old is not None and name == old["name"] and old["connection"] == opts.connection
    if name is None:
        while name is None or taken(name):
            name = random_name()
    elif not re.fullmatch(NAME_RE, name):
        die(f"--name {name}: lowercase letters, digits, _ . - only")
    elif not replace and taken(name):
        die(f"--name {name}: there is a container of that name{' on ' + opts.connection if opts.connection else ''}")
    items = [(flag, *parse_item(flag, spec))
             for flag in ("--cp", "--ro", "--rw", "--bind") for spec in getattr(opts, flag[2:])]
    repos = [parse_git(conf, spec) for spec in opts.git]
    adds = [parse_add_remote(conf, spec) for spec in opts.git_add_remote]

    # the workspace has one path, here while it is assembled and in the
    # container afterwards. not under /tmp, that is a tmpfs in the sandbox.
    # one carried on from has the path of the first: claude keeps a
    # conversation by its directory, and it is full of paths there
    base = os.environ.get("GENSOKYO_AGENT_TMPDIR", "/var/tmp/gensokyo-agent")
    workdir = old["workdir"] if old else os.path.join(base, name)
    for g in repos + adds:
        g["url"] = remote_url(g, name, podman, workdir)
        g["exists"] = check_remote(conf, g, name, g["url"])

    cmd = cmd or os.environ.get("AGENT_CMD", conf["defaultCmd"]).split()
    claude = os.path.basename(cmd[0]) == "claude"
    agent = agent_conf(conf, cmd)
    for flag in ("model", "effort"):
        if getattr(opts, flag) and flag not in agent.get("flags", {}):
            die(f"--{flag}: not one the wrapper knows for {cmd[0]}, give it its own after --")
    for flag in ("model", "effort"):
        if getattr(opts, flag):
            cmd += [arg.replace("%s", getattr(opts, flag)) for arg in agent["flags"][flag]]
    if claude:
        cmd += ["--mcp-config", f"{conf['closure']['at']}/share/gensokyo-agent/mcp.json"]

    # the closure: built here, or that of the workspace carried on from;
    # in the store of the workspace's host and rooted there, before the old
    # one is stopped, as a copy takes a while
    closure, servers, closure_from = conf["closure"]["default"], [], None
    scratch = None
    try:
        if opts.closure:
            if opts.connection is None:
                link = closure_root(name, taken)
            else:
                scratch = tempfile.mkdtemp(prefix="gensokyo-agent-closure.")
                link = os.path.join(scratch, "closure")
            closure, servers = build_closure(conf, opts.closure, link, call)
        elif old and old["closure"]:
            closure, servers, closure_from = old["closure"], old["servers"], old["connection"]
        custom = closure != conf["closure"]["default"]
        if custom and closure_from != opts.connection:
            copy_closure(conf, closure, closure_from, opts.connection, call)
        if custom and not (opts.closure and opts.connection is None):
            root_closure(conf, closure, name, opts.connection, call, taken)
    finally:
        if scratch:
            shutil.rmtree(scratch, ignore_errors=True)

    # what is copied is copied whole, and what is replaced is let go
    if old and old["running"] and (copy or replace):
        say(f"stopping {opts.from_}")
        if call([*old["podman"], "stop", old["name"]], stdout=subprocess.DEVNULL) != 0:
            die(f"--from {opts.from_}: podman stop failed")

    ctx = os.path.join(base, name + ".ctx")
    work = os.path.join(ctx, "work")
    if not os.path.isdir(base):
        os.makedirs(base)
        os.chmod(base, 0o1777)
    os.mkdir(ctx)
    try:
        if copy:
            src = f"{old['name']}:{workdir}"
            if call([*old["podman"], "cp", src, work]) != 0:
                die(f"--from {opts.from_}: podman cp {src} failed")
            carried_files(old, work, workdir)
        else:
            os.mkdir(work)
        root = os.path.join(ctx, "root")
        copy_writable(conf["root"], root)
        # COPY --chown makes the home the agent's only if it makes it
        shutil.rmtree(root + conf["home"], ignore_errors=True)
        os.makedirs(os.path.join(root, ".gensokyo-agent"), exist_ok=True)
        os.mkdir(os.path.join(ctx, "home"))
        if old:
            # the settings and the first-run state are this one's
            src = f"{old['name']}:{conf['home']}/.claude"
            if call([*old["podman"], "cp", src, os.path.join(ctx, "home", ".claude")]) != 0:
                die(f"--from {opts.from_}: podman cp {src} failed")
        write_home(os.path.join(ctx, "home"), workdir)
        login = token_args(conf, podman, cmd, os.path.join(ctx, "home"))

        mounts = []
        notes = {"history": [], "repositories": [], "files": [], "closure": [], "MCP servers": []}
        if old:
            elsewhere = old["connection"] != opts.connection
            history = [f"The conversation so far is that of the workspace `{old['name']}`, at this same path;"
                       f" the owner started this one in its place{', on another machine' if elsewhere else ''}"]
            if copy:
                history.append("Its files came along as it left them, uncommitted changes and all, but not what"
                               " was mounted there (volumes, the owner's directories) unless listed below, nor"
                               " anything of its home but `~/.claude`")
            else:
                history.append("Its files are not here: only what the owner brought, listed below. What was"
                               " not committed, or not fetched by the owner, is gone")
            if elsewhere:
                history.append("What it built in the nix store there is not in this one: a `result` link"
                               " may point at nothing")
            notes["history"].append(". ".join(history))
        for g in repos:
            clone_in(conf, g, work)
            notes["repositories"].append(
                f"`src/{g['repo']}`, on `{g['branch']}`, started from the owner's `{g['base']}`"
                f"{'' if g['full'] else ' with one commit of history'}. Commit here; there is nowhere"
                f" to push, the owner fetches. What they send arrives as `owner/<branch>`")
        for g in adds:
            if not os.path.lexists(os.path.join(work, "src", g["repo"], ".git")):
                die(f"--git-add-remote {g['top']}: the workspace has no src/{g['repo']} checkout"
                    f"{'' if copy else ', --no-copy left it behind'}; --git clones one")
            notes["repositories"].append(
                f"`src/{g['repo']}`, a checkout{' as `' + old['name'] + '` left it' if copy else ''}."
                " Commit here; there is nowhere to push, the owner fetches. What they send arrives as `owner/<branch>`")
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
        if claude:
            # read at every start, without asking: what the agent puts in it
            # the owner sees when claude asks to edit it
            if not os.path.lexists(os.path.join(work, ".mcp.json")):
                with open(os.path.join(work, ".mcp.json"), "w") as f:
                    f.write('{"mcpServers": {}}\n')
            if servers:
                notes["MCP servers"].append(f"{', '.join(f'`{n}`' for n in servers)}: the owner's, from the closure")
            notes["MCP servers"].append(
                "`.mcp.json` here is yours to fill in; claude reads it when it starts. Your edits of it"
                " are the owner's to approve, and count once they restart you. A server runs in this"
                " directory: one of a checkout `cd`s there in its command")
        setup = ""
        if agent.get("mcp"):
            # in the workspace, at the first start: its PWD and HOME are the ones to fill in
            mcp = f"\"$HOME\"/{shlex.quote(agent['mcp']['path'])}"
            jq = shlex.quote(MCP_EXPAND + " | " + MCP_FORMATS[agent["mcp"]["format"]])
            setup = (f"mkdir -p \"$(dirname {mcp})\"\n"
                     f"PWD=\"$PWD\" jq -r {jq} {conf['closure']['at']}/share/gensokyo-agent/mcp.json > {mcp}\n")
            if servers:
                notes["MCP servers"].append(f"{', '.join(f'`{n}`' for n in servers)}: the owner's, from the closure")
            notes["MCP servers"].append(
                f"`~/{agent['mcp']['path']}` is yours to fill in (`{os.path.basename(cmd[0])} mcp add`); it holds the owner's"
                " servers of the closure as well, written there when the workspace first started")
        if custom:
            made = f"built by the owner from `{opts.closure}`" if opts.closure else f"the one `{old['name']}` had"
            notes["closure"].append(
                f"`{conf['closure']['at']}`, {made}: its `bin` is first on your PATH."
                " A change to it takes a new workspace")
        with open(os.path.join(root, ".gensokyo-agent", "entrypoint"), "w") as f:
            f.write(entrypoint(cmd, opts.prompt, resume=bool(old), setup=setup))
            os.fchmod(f.fileno(), 0o755)
        with open(os.path.join(work, "CLAUDE.md"), "a") as f:
            f.write(claude_md(name, notes))
        # an agent that reads another file reads this one there
        if agent.get("instructions") and not os.path.lexists(os.path.join(work, agent["instructions"])):
            os.symlink("CLAUDE.md", os.path.join(work, agent["instructions"]))

        user = conf["user"]
        containerfile = "".join([
            "FROM scratch\n",
            "COPY root/ /\n",
            f"COPY --chown={user} home/ {conf['home']}/\n",
            f"COPY --chown={user} work/ {workdir}/\n",
        ])
        image = f"localhost/gensokyo-agent/{name}"
        with open(os.path.join(ctx, "Containerfile"), "w") as f:
            f.write(containerfile)
        if call([*podman, "build", "-t", image, "-f", os.path.join(ctx, "Containerfile"), ctx]) != 0:
            die("podman build failed")
    finally:
        remove_tree(ctx)

    # how it was made, for a later --from: the closure to bring along. the
    # checkouts are not recorded, --git-add-remote names them
    record = {
        "closure": closure if custom else None, "servers": servers if custom else [],
        "system": conf["system"], "cmd": cmd, "passthrough": passthrough,
        "opts": {k: v for k, v in vars(opts).items() if k not in ("git", "git_add_remote")},
    }
    args = ["--name", name, "--label", f"gensokyo-agent={name}", "--label", f"{LABEL}={json.dumps(record)}",
            "--log-driver", "none", "-w", workdir]
    args += conf["runArgs"]
    args += ["-v", f"{closure}:{conf['closure']['at']}:ro"]
    for want in ("gpu", "vm"):
        if getattr(opts, want):
            args += conf[f"{want}Args"]
    if opts.device:
        # the host's device, with the host's modes, so the agent needs the
        # groups of whoever runs this. podman keeps them only when it adds no
        # other: not the one the agent has for /dev/kvm
        kept, i = [], 0
        while i < len(args):
            if args[i] == "--group-add":
                i += 2
            else:
                kept.append(args[i])
                i += 1
        args = kept + ["--group-add", "keep-groups"]
        for spec in opts.device:
            args += ["--device", spec]
    args += login
    for spec in opts.secret:
        args += ["--secret", spec]
    args += mounts
    for spec in opts.publish:
        args += ["-p", spec]
    tty = sys.stdin.isatty()
    if tty:
        args.append("-it")

    pm = shlex.join(["podman"] + podman[1:])
    if replace:
        # the old one steps aside for the new one to be created under its
        # name, and goes only once that has worked
        aside, n = f"{name}.replaced", 1
        while taken(aside):
            aside, n = f"{name}.replaced{n}", n + 1
        if call([*podman, "rename", name, aside]) != 0:
            die(f"--from {opts.from_}: podman rename failed, it is as it was")
        if call([*podman, "create", *args, *passthrough, image, "/.gensokyo-agent/entrypoint"], stdout=subprocess.DEVNULL) != 0:
            call([*podman, "rename", aside, name])
            die(f"podman create failed; {name} is as it was, but stopped")
        call([*podman, "rm", aside], stdout=subprocess.DEVNULL)
        if old["image"]:
            call([*podman, "rmi", old["image"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        argv = [*podman, "start", "-a", *(["-i"] if tty else []), name]
    else:
        argv = [*podman, "run", *args, *passthrough, image, "/.gensokyo-agent/entrypoint"]
    for g in repos + adds:
        add_remote(conf, g, name, g["url"], g["exists"])

    say(f"workspace {name} at {workdir}")
    if replace:
        say(f"  in place of the workspace {name} it carries on from, now removed")
    elif old:
        opm = shlex.join(["podman"] + old["podman"][1:])
        say(f"  carries on from {opts.from_}, which is left as it was: {opm} rm {old['name']} && {opm} rmi localhost/gensokyo-agent/{old['name']}")
    say(f"  leave with ctrl-p ctrl-q, return with: {pm} attach {name}")
    say(f"  once it has stopped: {pm} start -ai {name}")
    for g in repos + adds:
        say(f"  its work, while it runs: git -C {g['top']} fetch {name}")
    say(f"  remove: {pm} rm {name} && {pm} rmi {image}")
    if custom:
        say(f"  its closure is kept until a later one finds it gone, or: rm -r {os.path.join(state_dir(), name)}"
            f"{' there' if opts.connection else ''}")
    if opts.tunnel:
        runtime = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "gensokyo-agent")
        os.makedirs(runtime, exist_ok=True)
        sock = os.path.join(runtime, f"{name}.ssh")
        forwards = [arg for spec in opts.tunnel for arg in ("-L", spec)]
        if call([conf["ssh"], "-f", "-N", "-M", "-S", sock, "-o", "ExitOnForwardFailure=yes", *forwards, *target]) != 0:
            say(f"  no tunnel, ssh failed; by hand: ssh -N {shlex.join(forwards + target)}")
        else:
            say(f"  tunnel {' '.join(opts.tunnel)}, until: ssh -S {sock} -O exit {target[-1]}")
    if debug:
        print("+ " + shlex.join(argv), file=sys.stderr)
    sys.stdout.flush()
    sys.stderr.flush()
    os.execvp(argv[0], argv)


def merge_tree(src, dst):
    """src into dst, files of the same name replaced, none removed: a
    transcript only grows, and is named by its session."""
    for d, dirs, files in os.walk(src):
        out = os.path.join(dst, os.path.relpath(d, src))
        os.makedirs(out, exist_ok=True)
        for f in files:
            target = os.path.join(out, f)
            if os.path.lexists(target) and not os.path.isdir(target):
                os.unlink(target)
            shutil.copy2(os.path.join(d, f), target, follow_symlinks=False)


def history_args(argv, prog, takes_dir):
    p = argparse.ArgumentParser(prog=f"gensokyo-agent {prog}", usage=USAGE, add_help=False, allow_abbrev=False)
    p.add_argument("-c", "--connection", action="append", default=[])
    if takes_dir:
        p.add_argument("dir", nargs="?")
    return p.parse_args(argv)


def each_workspace(conf, conns):
    """(where, podman, name) of every workspace here and on every connection,
    or on those named; one this host has under two connections, once"""
    if not conns:
        out = subprocess.run([conf["podman"], "system", "connection", "ls", "--format", "json"],
                             stdout=subprocess.PIPE, text=True).stdout
        conns = [None] + [c["Name"] for c in json.loads(out or "[]")]
    seen = set()
    for conn in conns:
        podman = [conf["podman"]] + (["-c", conn] if conn else [])
        where = conn or "local"
        try:
            r = subprocess.run([*podman, "ps", "-a", "--filter", "label=gensokyo-agent", "--format", "json"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=60)
            found = json.loads(r.stdout or "[]") if r.returncode == 0 else None
        except (subprocess.TimeoutExpired, ValueError):
            found = None
        if found is None:
            say(f"{where}: not reached, skipped")
            continue
        for c in found:
            if c["Id"] not in seen:
                seen.add(c["Id"])
                yield where, podman, c["Names"][0]


def projects_tar(conf, podman, name):
    """The projects/ of a workspace's claude home, as podman cp streams it;
    what the agent wrote, so read as such. None when it has none"""
    r = subprocess.run([*podman, "cp", f"{name}:{conf['home']}/.claude/projects", "-"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if r.returncode != 0:
        return None
    try:
        return tarfile.open(fileobj=io.BytesIO(r.stdout))
    except tarfile.TarError:
        return None


def first_prompt(lines):
    """What the owner said first in a transcript, on one line."""
    for line in lines:
        try:
            d = json.loads(line)
            if d.get("type") != "user" or d.get("isMeta"):
                continue
            content = d["message"]["content"]
        except (ValueError, LookupError, TypeError, AttributeError):
            continue
        if isinstance(content, list):
            content = next((c.get("text") for c in content if isinstance(c, dict) and c.get("type") == "text"), None)
        # commands, reminders and the like come wrapped in tags
        if isinstance(content, str) and content.strip() and not content.lstrip().startswith("<"):
            return " ".join(content.split())
    return ""


SESSION = re.compile(r"^(?:projects/)?[^/]+/([^/]+)\.jsonl$")


def list_history(conf, argv):
    """--history: a line for every conversation, the oldest first."""
    opts = history_args(argv, "--history", False)
    rows = []
    for where, podman, name in each_workspace(conf, opts.connection):
        tar = projects_tar(conf, podman, name)
        for m in tar.getmembers() if tar else []:
            s = SESSION.match(m.name)
            if s and m.isfile():
                rows.append((m.mtime, f"{where}/{name}", m.size, s[1], first_prompt(tar.extractfile(m))))
    own = os.path.expanduser("~/.claude/projects")
    for d, _, files in os.walk(own):
        for f in files:
            path = os.path.join(d, f)
            s = SESSION.match(os.path.relpath(path, own))
            if s:
                with open(path, "rb") as fh:
                    rows.append((os.path.getmtime(path), "local/_owner", os.path.getsize(path), s[1], first_prompt(fh)))
    rows.sort()
    width = max([len(r[1]) for r in rows] + [0])
    for mtime, ws, size, session, prompt in rows:
        when = time.strftime("%Y-%m-%d %H:%M", time.localtime(mtime))
        print(f"{when}  {ws:<{width}}  {size / 1e6:6.1f}M  {session[:8]}  {prompt[:80]}")
    say(f"{len(rows)} conversation{'' if len(rows) == 1 else 's'}, {sum(r[2] for r in rows) / 1e6:.1f} MB; "
        "gensokyo-agent --copy-history to keep a copy")


def copy_history(conf, argv):
    """--copy-history: every workspace's projects/ gathered in a directory
    here, merged into what an earlier run left there."""
    opts = history_args(argv, "--copy-history", True)
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    dest = os.path.abspath(os.path.expanduser(opts.dir or os.path.join(data, "gensokyo-agent", "history")))
    os.makedirs(dest, exist_ok=True)
    gathered = 0
    for where, podman, name in each_workspace(conf, opts.connection):
        tar = projects_tar(conf, podman, name)
        if tar is None:
            say(f"{where}/{name}: no conversations")
            continue
        with tempfile.TemporaryDirectory(dir=dest, prefix=".") as tmp:
            # nothing outside tmp, no devices, no links that lead out
            tar.extractall(tmp, filter="data")
            got = os.path.join(tmp, "projects")
            if os.path.isdir(got):
                merge_tree(got, os.path.join(dest, where, name, "projects"))
                gathered += 1
    own = os.path.expanduser("~/.claude/projects")
    if os.path.isdir(own):
        merge_tree(own, os.path.join(dest, "local", "_owner", "projects"))
    say(f"{gathered} workspaces{' and yours' if os.path.isdir(own) else ''} in {dest}")


def main():
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda *_: sys.exit(1))
    if sys.argv[1:2] == ["--history"]:
        sys.exit(list_history(load_conf(), sys.argv[2:]))
    if sys.argv[1:2] == ["--copy-history"]:
        sys.exit(copy_history(load_conf(), sys.argv[2:]))
    opts, cmd, passthrough = parse_args(sys.argv[1:])
    conf = load_conf()
    if opts is None:
        sys.exit(run_here(conf, cmd))
    new_workspace(conf, opts, cmd, passthrough)


if __name__ == "__main__":
    main()
