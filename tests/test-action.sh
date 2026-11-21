#!/bin/bash
# action.yml publishes a verified bundle to a Sond registry: inputs reach the shell only through env
# (never ${{ inputs.* }} inside run:), the token and the signing key are written to files only
# the runner user can read and removed afterwards, `sondpkg publish` runs and its object=,
# log_index= and tree_size= lines become the outputs, an idempotent re-run (exit 3) is not a
# failure, and the inclusion proof is checked with `sondpkg verify-published`.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec python3 - "$here/action.yml" <<'PY'
import re, sys, yaml
fail = 0
def check(cond, what):
    global fail
    print(("ok   " if cond else "FAIL ") + what)
    fail |= not cond
try:
    a = yaml.safe_load(open(sys.argv[1]))
except Exception as e:
    print(f"FAIL action.yml parses ({e})"); print("test-action: FAIL"); sys.exit(1)
inputs = a.get("inputs") or {}
steps = (a.get("runs") or {}).get("steps") or []
check((a.get("runs") or {}).get("using") == "composite", "a composite action")
for i in ["bundle", "token", "signing-key"]:
    check(inputs.get(i, {}).get("required") is True, f"input {i} is required")
check(inputs.get("url", {}).get("default") == "https://dist.sond.dev", "url defaults to https://dist.sond.dev")
check("distro-pkg-ref" in inputs, "input distro-pkg-ref")
runs = [s.get("run", "") for s in steps]
check(not any("${{" in r for r in runs), "no ${{ }} expression inside any run: (inputs go through env)")
pub = next((s for s in steps if s.get("id") == "publish"), {})
r = pub.get("run", "")
check("umask 077" in r, "the secrets are written with umask 077")
check("trap" in r and 'rm -rf -- "$secrets"' in r, "the secrets directory is removed on exit")
check(re.search(r"sondpkg(\[@\]\})?\"? publish ", r) is not None, "the step runs sondpkg publish")
check(re.search(r'>>\s*"\$GITHUB_OUTPUT"', r) is not None, "publish's stdout becomes the step outputs")
check(re.search(r"\b3\)", r) is not None or "-eq 3" in r or "= 3" in r, "exit 3 (already published) is accepted")
check(re.search(r"sondpkg(\[@\]\})?\"? verify-published ", r) is not None, "the inclusion proof is verified")
check(inputs.get("log-key", {}).get("default") == "072f2d42e0c81e0d075a50585e63bfbe74f2f8d65a0d6db2c1185f432d5a44e8", "the log key of dist.sond.dev is pinned by default")
check(re.search(r'verify-published "\$IN_BUNDLE" --url "\$IN_URL" --log-key "\$IN_LOG_KEY"', r) is not None, "the proof is checked against the pinned log key")
check((pub.get("env") or {}).get("IN_LOG_KEY") == "${{ inputs.log-key }}", "the key reaches the step through env")
outs = a.get("outputs") or {}
for o in ["object", "log_index", "tree_size"]:
    check(outs.get(o, {}).get("value") == "${{ steps.publish.outputs.%s }}" % o, f"output {o} from the publish step")
env = pub.get("env") or {}
check(any("inputs.token" in str(v) for v in env.values()) and any("inputs.signing-key" in str(v) for v in env.values()), "token and key reach the step through env")

# Behaviour: the step runs against a fake sondpkg that fails; the failure comes back as the
# step's exit code and no secret is left on disk.
import os, subprocess, tempfile
with tempfile.TemporaryDirectory() as tmp:
    d = os.path.join(tmp, "sond", "sond-distro-pkg")
    os.makedirs(os.path.join(d, ".git")); os.makedirs(os.path.join(d, "sondpkg", "bin"))
    with open(os.path.join(d, "sondpkg", "bin", "sondpkg"), "w") as f:
        f.write("import sys\nprint('object=x')\nsys.exit(1)\n")
    env = dict(os.environ, RUNNER_TEMP=tmp, IN_BUNDLE="b", IN_URL="http://127.0.0.1:1", IN_REF="main",
               IN_LOG_KEY="0" * 64, SOND_PUBLISH_TOKEN="tok", SOND_SIGNING_KEY="key",
               GITHUB_OUTPUT=os.path.join(tmp, "out"))
    p = subprocess.run(["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", r],
                       env=env, capture_output=True, text=True)
    check(p.returncode == 1, f"a failed publish fails the step with its exit code (got {p.returncode})")
    left = [n for n in os.listdir(tmp) if n.startswith("sond-publish.")]
    check(not left, f"no secrets directory is left after a failure (left {left})")
    check("rmdir" not in p.stderr, "the clean-up itself does not fail")
print("test-action: " + ("FAIL" if fail else "OK"))
sys.exit(fail)
PY
