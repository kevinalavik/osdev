import os
import sys
import hashlib
import shutil
import tempfile
import urllib.request
import zipfile
import tarfile

def log_module(path):
    print(f"\tMODULE  {path}")

def log_step(msg):
    print(f"\t    >>> {msg}")

def log_fail(msg):
    print(f"\t    !!! {msg}")

def parse_list(path):
    """
    Parse modules.list format:
    type url expected_hash out_path
    type can be: file, archive
    """
    modules = []

    with open(path, "r", encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            words = []
            current = ""

            for ch in line:
                if ch == "#":
                    break
                elif ch.isspace():
                    if current:
                        words.append(current)
                        current = ""
                elif ch != "\n":
                    current += ch

            if current:
                words.append(current)

            if not words:
                continue

            if len(words) != 4:
                log_fail(f"{path}:{lineno} (expected 4 fields: type url hash out_path)")
                sys.exit(1)

            modules.append(words)

    return modules

def sha256_file(path):
    sha = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            sha.update(chunk)
    return sha.hexdigest()

def verify_file(path, expected_hash):
    actual = sha256_file(path)
    if actual != expected_hash:
        log_fail(f"sha256 mismatch for {path}, got {actual} expected {expected_hash}")
        return False
    return True

def download_file(url, dest_path):
    log_step(f"download {url}")
    urllib.request.urlretrieve(url, dest_path)

def extract_archive(archive_path, dest_dir):
    log_step(f"extract {archive_path} -> {dest_dir}")
    os.makedirs(dest_dir, exist_ok=True)

    if archive_path.endswith(".zip"):
        with zipfile.ZipFile(archive_path, "r") as zf:
            for member in zf.infolist():
                parts = member.filename.split('/', 1)
                if len(parts) == 2:
                    target_path = os.path.join(dest_dir, parts[1])
                else:
                    target_path = os.path.join(dest_dir, parts[0])

                if member.is_dir():
                    os.makedirs(target_path, exist_ok=True)
                else:
                    os.makedirs(os.path.dirname(target_path), exist_ok=True)
                    with zf.open(member) as source, open(target_path, "wb") as target:
                        shutil.copyfileobj(source, target)

    elif archive_path.endswith((".tar.gz", ".tgz", ".tar")):
        with tarfile.open(archive_path, "r:*") as tf:
            for member in tf.getmembers():
                path_parts = member.name.split('/', 1)
                if len(path_parts) == 2:
                    member.name = path_parts[1]
                    tf.extract(member, path=dest_dir)
                elif member.isdir():
                    continue
                else:
                    tf.extract(member, path=dest_dir)
    else:
        log_fail(f"unsupported archive format: {archive_path}")
        sys.exit(1)


def pull(modules):
    with tempfile.TemporaryDirectory(prefix="modules_") as tmpdir:
        for type_, url, expected_hash, out_path in modules:
            log_module(out_path)

            if type_ == "file":
                if os.path.exists(out_path):
                    log_step("already exists, verifying")
                    if verify_file(out_path, expected_hash):
                        log_step("up-to-date")
                        continue
                    else:
                        log_fail("existing file is invalid, re-downloading")

                tmp_path = os.path.join(tmpdir, os.path.basename(url))
                download_file(url, tmp_path)

                log_step("verify")
                if not verify_file(tmp_path, expected_hash):
                    sys.exit(1)

                log_step("install")
                os.makedirs(os.path.dirname(out_path), exist_ok=True)
                shutil.move(tmp_path, out_path)

            elif type_ == "archive":
                tmp_path = os.path.join(tmpdir, os.path.basename(url))
                download_file(url, tmp_path)

                log_step("verify")
                if not verify_file(tmp_path, expected_hash):
                    sys.exit(1)

                extract_archive(tmp_path, out_path)

            else:
                log_fail(f"unknown module type: {type_}")
                sys.exit(1)

def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <modules.list>")
        sys.exit(1)

    modules = parse_list(sys.argv[1])
    pull(modules)

if __name__ == "__main__":
    main()
