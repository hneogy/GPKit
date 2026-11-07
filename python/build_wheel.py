#!/usr/bin/env python3
"""pygpkit's wheel, written with Python's standard library alone.

    python3 build_wheel.py --library PATH --platform TAG [--out DIR]

PATH is the native library built from this folder (swift build -c release --product pygpkit_core), and TAG the
wheel's platform tag, such as macosx_13_0_universal2, manylinux_2_39_x86_64 or win_amd64. The wheel holds the
Python package, the library beside it, and GPKit's LICENSE and NOTICE. A wheel is a zip file with three files of
metadata (PEP 427 and the core metadata specification); nothing more is needed to write one, so no build tool is
installed for it.
"""

import argparse
import base64
import hashlib
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "pygpkit"


def version() -> str:
    with open(os.path.join(HERE, "src", NAME, "__init__.py"), encoding="utf-8") as f:
        match = re.search(r'^__version__ = "([^"]+)"$', f.read(), re.M)
    if not match:
        sys.exit("no __version__ in the package")
    return match.group(1)


def metadata(v: str) -> str:
    with open(os.path.join(HERE, "README.md"), encoding="utf-8") as f:
        description = f.read()
    return "\n".join([
        "Metadata-Version: 2.1",
        f"Name: {NAME}",
        f"Version: {v}",
        "Summary: GPKit from Python: OMM and TLE reading, TLE writing, SGP4 and passes, the numbers GPKit gives to the bit",
        "Home-page: https://github.com/hneogy/GPKit",
        "License: MIT",
        "Requires-Python: >=3.9",
        "Classifier: License :: OSI Approved :: MIT License",
        "Classifier: Programming Language :: Python :: 3",
        "Classifier: Topic :: Scientific/Engineering :: Astronomy",
        "Description-Content-Type: text/markdown",
        "",
        description,
    ])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--out", default=os.path.join(HERE, "dist"))
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9_]+", args.platform):
        sys.exit(f"{args.platform} is not a platform tag")

    v = version()
    dist_info = f"{NAME}-{v}.dist-info"
    tag = f"py3-none-{args.platform}"
    files = {}   # path in the wheel -> bytes
    package = os.path.join(HERE, "src", NAME)
    for name in sorted(os.listdir(package)):
        if name.endswith(".py") or name == "py.typed":
            with open(os.path.join(package, name), "rb") as f:
                files[f"{NAME}/{name}"] = f.read()
    with open(args.library, "rb") as f:
        files[f"{NAME}/{os.path.basename(args.library)}"] = f.read()
    for name in ("LICENSE", "NOTICE"):
        with open(os.path.join(HERE, "..", name), "rb") as f:
            files[f"{dist_info}/{name}"] = f.read()
    files[f"{dist_info}/METADATA"] = metadata(v).encode("utf-8")
    files[f"{dist_info}/WHEEL"] = "\n".join([
        "Wheel-Version: 1.0", "Generator: pygpkit build_wheel.py", "Root-Is-Purelib: false", f"Tag: {tag}", "",
    ]).encode("utf-8")

    def digest(data: bytes) -> str:
        return "sha256=" + base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode("ascii")

    record = [f"{path},{digest(data)},{len(data)}" for path, data in files.items()]
    record.append(f"{dist_info}/RECORD,,")
    files[f"{dist_info}/RECORD"] = ("\n".join(record) + "\n").encode("utf-8")

    os.makedirs(args.out, exist_ok=True)
    wheel = os.path.join(args.out, f"{NAME}-{v}-{tag}.whl")
    with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as z:
        for path, data in files.items():
            info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
            # the library executable, the rest plain files
            info.external_attr = (0o755 if path.endswith((".so", ".dylib", ".dll")) else 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    print(wheel)


if __name__ == "__main__":
    main()
