#!/usr/bin/env python3
import argparse
import json
import os
import signal
import subprocess
import time
from pathlib import Path


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, ValueError):
        return False
    except PermissionError:
        return True


def release_lock(lock: Path) -> None:
    try:
        (lock / "owner").unlink(missing_ok=True)
        lock.rmdir()
    except OSError:
        pass


def acquire_lock(lock: Path, wait_seconds: float = 30.0) -> None:
    deadline = time.monotonic() + wait_seconds
    while True:
        try:
            lock.mkdir()
            (lock / "owner").write_text(f"{os.getpid()}\n", encoding="utf-8")
            return
        except FileExistsError:
            try:
                owner = int((lock / "owner").read_text(encoding="utf-8").strip())
            except (OSError, ValueError):
                owner = 0
            if owner and not pid_alive(owner):
                release_lock(lock)
                continue
            if time.monotonic() >= deadline:
                raise TimeoutError(f"startup lock timed out: {lock}")
            time.sleep(0.1)


def stop_process(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def append_timeout(log: Path, timeout: float) -> None:
    event = {
        "type": "error",
        "error": {
            "type": "TabocAttemptTimeout",
            "message": f"OpenCode attempt exceeded {timeout:g} seconds",
        },
    }
    with log.open("ab") as stream:
        if log.stat().st_size:
            stream.write(b"\n")
        stream.write(json.dumps(event, ensure_ascii=False).encode("utf-8") + b"\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--startup-lock", required=True)
    parser.add_argument("--startup-hold", type=float, default=1.5)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    command = options.command[1:] if options.command[:1] == ["--"] else options.command
    if options.timeout <= 0 or not command:
        parser.error("timeout must be positive and command is required")
    log = Path(options.log)
    lock = Path(options.startup_lock)
    acquire_lock(lock)
    try:
        with log.open("wb") as stream:
            process = subprocess.Popen(
                command,
                stdout=stream,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        deadline = time.monotonic() + max(0.0, options.startup_hold)
        while process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.05)
    finally:
        release_lock(lock)
    try:
        return process.wait(timeout=options.timeout)
    except subprocess.TimeoutExpired:
        stop_process(process)
        append_timeout(log, options.timeout)
        return 124


if __name__ == "__main__":
    raise SystemExit(main())
