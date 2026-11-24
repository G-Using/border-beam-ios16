#!/usr/bin/env python3
"""Minimal .deb builder: ar archive + gzipped tar, no dpkg required.

Usage:
    python3 tools/pack_deb.py --payload stage --arch iphoneos-arm64 --out out/x.deb

The payload directory becomes the data.tar root (paths are taken verbatim,
so put files under stage/var/jb/... for a rootless package).
"""
import argparse
import gzip
import io
import os
import tarfile
import time


def _add_tree(tar, base, rel, arcname):
    path = os.path.join(base, rel)
    st = os.lstat(path)
    info = tarfile.TarInfo(arcname)
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "wheel"
    info.mtime = int(time.time())

    if os.path.isdir(path) and not os.path.islink(path):
        info.type = tarfile.DIRTYPE
        info.mode = 0o755
        tar.addfile(info)
        for name in sorted(os.listdir(path)):
            child_rel = rel + "/" + name if rel else name
            child_arc = arcname.rstrip("/") + "/" + name
            _add_tree(tar, base, child_rel, child_arc)
    else:
        with open(path, "rb") as f:
            data = f.read()
        info.type = tarfile.REGTYPE
        info.size = len(data)
        info.mode = 0o755 if is_executable_file(path) else 0o644
        tar.addfile(info, io.BytesIO(data))


def is_executable_file(path):
    """Only real binaries get +x: the main .app executable, dylibs, Frameworks, /bin."""
    p = path.replace("\\", "/")
    parts = p.split("/")
    app_idx = next((i for i, seg in enumerate(parts) if seg.endswith(".app")), None)
    if app_idx is not None:
        rest = parts[app_idx + 1:]
        if rest and rest[0] == "Frameworks":
            return True
        if len(rest) == 1:
            low = rest[0].lower()
            return not low.endswith((
                ".plist", ".png", ".jpg", ".jpeg", ".json", ".strings", ".nib",
                ".car", ".metallib", ".metal", ".ttf", ".otf", ".mo", ".lproj",
            ))
    if "/bin/" in p or p.endswith(".dylib"):
        return True
    return False


def build_tar_gz(base, entries):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for rel, arcname in entries:
            _add_tree(tar, base, rel if rel else ".", arcname)
    raw = buf.getvalue()
    out = io.BytesIO()
    with gzip.GzipFile(fileobj=out, mode="wb", mtime=0) as gz:
        gz.write(raw)
    return out.getvalue()


def ar_member(name, data):
    header = (
        name.encode().ljust(16, b" ")
        + b"0".ljust(12, b" ")
        + b"0".ljust(6, b" ")
        + b"0".ljust(6, b" ")
        + b"100644".ljust(8, b" ")
        + str(len(data)).encode().ljust(10, b" ")
        + b"`\n"
    )
    assert len(header) == 60, len(header)
    pad = b"\n" if len(data) % 2 else b""
    return header + data + pad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--payload", required=True)
    ap.add_argument("--arch", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--package", default="com.borderbeam.demo")
    ap.add_argument("--name", default="BorderBeam Demo")
    ap.add_argument("--version", default="1.0.0")
    ap.add_argument("--maintainer", default="local")
    ap.add_argument("--author", default="ismnoiet (iOS 15/16 port)")
    ap.add_argument(
        "--description",
        default="Animated Metal border beam for SwiftUI. Demo app for iOS 15/16 "
                "rootless and roothide jailbreaks.",
    )
    ap.add_argument("--section", default="Applications")
    ap.add_argument("--depends", default="")
    args = ap.parse_args()

    base = os.path.abspath(args.payload)
    if not os.path.isdir(base):
        raise SystemExit(f"payload not found: {base}")

    # data.tar.gz: every top-level entry of the payload, prefixed with "./"
    top = [n for n in sorted(os.listdir(base)) if n != ".debian"]
    data_entries = [(n, "./" + n) for n in top]
    data_tgz = build_tar_gz(base, data_entries)

    control = (
        f"Package: {args.package}\n"
        f"Name: {args.name}\n"
        f"Version: {args.version}\n"
        f"Architecture: {args.arch}\n"
        f"Description: {args.description}\n"
        f"Maintainer: {args.maintainer}\n"
        f"Author: {args.author}\n"
        f"Section: {args.section}\n"
        "Priority: optional\n"
    )
    if args.depends:
        control += f"Depends: {args.depends}\n"

    ctrl_dir = os.path.join(base, ".debian")
    os.makedirs(ctrl_dir, exist_ok=True)
    with open(os.path.join(ctrl_dir, "control"), "w", encoding="utf-8", newline="\n") as f:
        f.write(control)
    ctrl_tgz = build_tar_gz(ctrl_dir, [("control", "./control")])

    deb = (
        b"!<arch>\n"
        + ar_member("debian-binary", b"2.0\n")
        + ar_member("control.tar.gz", ctrl_tgz)
        + ar_member("data.tar.gz", data_tgz)
    )

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(deb)
    print(f"wrote {out} ({len(deb)} bytes, arch={args.arch})")


if __name__ == "__main__":
    main()
