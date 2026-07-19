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


def append_timeout(log: Path, kind: str, timeout: float) -> None:
    label = "idle" if kind == "Idle" else "hard"
    event = {
        "type": "error",
        "error": {
            "type": f"TabocAttempt{kind}Timeout",
            "message": f"OpenCode attempt exceeded {timeout:g} seconds {label} timeout",
        },
    }
    with log.open("ab") as stream:
        if log.stat().st_size:
            stream.write(b"\n")
        stream.write(json.dumps(event, ensure_ascii=False).encode("utf-8") + b"\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--idle-timeout", type=float)
    parser.add_argument("--hard-timeout", type=float)
    parser.add_argument("--timeout", type=float, help=argparse.SUPPRESS)
    parser.add_argument("--log", required=True)
    parser.add_argument("--startup-lock", required=True)
    parser.add_argument("--startup-hold", type=float, default=1.5)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    command = options.command[1:] if options.command[:1] == ["--"] else options.command
    idle_timeout = options.idle_timeout if options.idle_timeout is not None else options.timeout
    hard_timeout = (
        options.hard_timeout
        if options.hard_timeout is not None
        else (idle_timeout * 3 if idle_timeout else None)
    )
    if not idle_timeout or idle_timeout <= 0 or not hard_timeout or hard_timeout <= 0 or not command:
        parser.error("idle timeout, hard timeout, and command must be positive")
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
    started = time.monotonic()
    last_activity = started
    observed_size = log.stat().st_size
    while True:
        code = process.poll()
        if code is not None:
            return code
        now = time.monotonic()
        try:
            size = log.stat().st_size
        except OSError:
            size = observed_size
        if size != observed_size:
            observed_size = size
            last_activity = now
        if now - started >= hard_timeout:
            stop_process(process)
            append_timeout(log, "Hard", hard_timeout)
            return 124
        if now - last_activity >= idle_timeout:
            stop_process(process)
            append_timeout(log, "Idle", idle_timeout)
            return 124
        time.sleep(0.25)


if __name__ == "__main__":
    raise SystemExit(main())
