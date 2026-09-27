# /// script
# requires-python = ">=3.11"
# ///
"""リポジトリ (.env でプレースホルダ置換) と実機の差分を表示する"""

import argparse
import difflib
import io
import os
import re
import shlex
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PLACEHOLDER = re.compile(rb"<([A-Z][A-Z0-9_]*)>")
SSH = os.environ.get("SSH") or (r"C:\Windows\System32\OpenSSH\ssh.exe" if os.name == "nt" else "ssh")


def load_env(path):
    env = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def tracked(filters):
    out = subprocess.run(
        ["git", "ls-files", "-s", "home", "rootfs"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    for line in out.splitlines():
        meta, path = line.split("\t", 1)
        if path.endswith((".example", ".gitkeep")):
            continue
        if filters and not any(f in path for f in filters):
            continue
        yield path, meta.split()[0] == "100755"


def target(path, rootfs_user):
    top, rest = path.split("/", 1)
    if top == "home":
        user, sub = rest.split("/", 1)
        return user, f"/home/{user}/{sub}"
    return rootfs_user, "/" + rest


def fetch(host, user, paths):
    remote = "tar -cPf - --ignore-failed-read -- " + " ".join(shlex.quote(p) for p in paths)
    r = subprocess.run([SSH, "-o", "BatchMode=yes", f"{user}@{host}", remote], capture_output=True)
    files, errors = {}, {}
    if r.stdout:
        with tarfile.open(fileobj=io.BytesIO(r.stdout)) as tar:
            for m in tar:
                if m.isfile():
                    files["/" + m.name.lstrip("/")] = (tar.extractfile(m).read(), bool(m.mode & 0o111))
    for line in r.stderr.decode(errors="replace").splitlines():
        m = re.match(r"tar: (/\S+): (?:Cannot \w+: )?(.*)", line)
        if m:
            errors[m.group(1)] = m.group(2)
    if r.returncode not in (0, 1) and not files:
        sys.exit(f"ssh {user}@{host} failed: {r.stderr.decode(errors='replace').strip()}")
    return files, errors


def render(data, env, missing):
    def sub(m):
        key = m.group(1).decode()
        if key in env:
            return env[key].encode()
        missing.add(key)
        return m.group(0)
    return PLACEHOLDER.sub(sub, data.replace(b"\r\n", b"\n"))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-s", "--stat", action="store_true", help="差分の本文を出さず一覧のみ")
    ap.add_argument("filters", nargs="*", help="パスの部分一致で対象を絞る")
    args = ap.parse_args()

    env_path = ROOT / ".env"
    if not env_path.exists():
        sys.exit(".env がない (.env.example を参照)")
    env = load_env(env_path)
    host = env.get("DEPLOY_HOST") or sys.exit("DEPLOY_HOST が未設定")
    rootfs_user = env.get("ROOTFS_USER", "owner")

    groups = {}
    for path, exe in tracked(args.filters):
        user, remote = target(path, rootfs_user)
        groups.setdefault(user, []).append((path, remote, exe))

    counts = {"OK": 0, "DIFF": 0, "MISSING": 0, "NOREAD": 0}
    missing_keys = set()
    for user, items in groups.items():
        files, errors = fetch(host, user, [r for _, r, _ in items])
        for path, remote, exe in items:
            if remote not in files:
                err = errors.get(remote, "not found")
                status = "NOREAD" if "Permission denied" in err else "MISSING"
                counts[status] += 1
                print(f"{status:8} {remote}  ({err})")
                continue
            actual, actual_exe = files[remote]
            expected = render((ROOT / path).read_bytes(), env, missing_keys)
            notes = []
            if actual != expected:
                notes.append("content")
            # /boot は vfat で実行ビットが常に立つ
            if actual_exe != exe and not remote.startswith("/boot/"):
                notes.append(f"mode (repo {'+x' if exe else '-x'})")
            if not notes:
                counts["OK"] += 1
                continue
            counts["DIFF"] += 1
            print(f"DIFF     {remote}  [{', '.join(notes)}]")
            if not args.stat and actual != expected:
                diff = difflib.unified_diff(
                    actual.decode(errors="replace").splitlines(keepends=True),
                    expected.decode(errors="replace").splitlines(keepends=True),
                    f"{user}@{host}:{remote}", f"repo:{path}",
                )
                sys.stdout.writelines(diff)
                print()

    if missing_keys:
        print(f"未設定のプレースホルダ: {', '.join(sorted(missing_keys))}", file=sys.stderr)
    print(" ".join(f"{k}={v}" for k, v in counts.items()))
    sys.exit(1 if counts["DIFF"] or counts["MISSING"] else 0)


if __name__ == "__main__":
    main()
