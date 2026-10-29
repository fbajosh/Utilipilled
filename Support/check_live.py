#!/usr/bin/env python3
"""Exercise REAL system alert volume. No camera is opened.

Quit Utilipilled first. The production lock is held throughout this test to prevent
an installed app from competing with isolated sessions. A zero starting volume
is rejected because it cannot prove mute ownership or crash restoration.
"""
import contextlib
import fcntl
import json
import os
import pathlib
import platform
import select
import signal
import shutil
import stat
import subprocess
import tempfile
import time

BASE = pathlib.Path(__file__).resolve().parents[1]
EXE = BASE / "dist/Utilipilled.app/Contents/MacOS/Utilipilled"
PRODUCTION = pathlib.Path.home() / "Library/Application Support/CameraQuiet"


def script(source):
    return subprocess.check_output(
        ["/usr/bin/osascript", "-e", source], text=True, timeout=5
    ).strip()


def settings():
    return dict(item.strip().split(":") for item in script("get volume settings").split(","))


def alert():
    return int(settings()["alert volume"])


def require_audible_baseline(original):
    value = int(original["alert volume"])
    if not 1 <= value <= 100:
        raise RuntimeError("Set Alert volume above zero before running the live checks.")
    return value


@contextlib.contextmanager
def production_lock(directory=PRODUCTION):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    lock_fd = None
    try:
        metadata = os.fstat(directory_fd)
        if metadata.st_uid != os.geteuid() or metadata.st_mode & 0o022:
            raise RuntimeError("The production recovery directory must be owned by you and not publicly writable.")
        lock_fd = os.open("instance.lock", os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW,
                          0o600, dir_fd=directory_fd)
        metadata = os.fstat(lock_fd)
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.geteuid()
                or metadata.st_nlink != 1 or metadata.st_mode & 0o077):
            raise RuntimeError("Unsafe production instance lock; the live test will not continue.")
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("Quit Utilipilled/CameraQuiet and wait for recovery before running this test.") from error
        try:
            os.stat("recovery.json", dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise RuntimeError("An existing recovery record needs attention. Run Utilipilled --recover first.")
        yield
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
        os.close(directory_fd)


def wait_for(test, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if test():
            return
        time.sleep(0.15)
    raise RuntimeError("Timed out waiting for restoration; recovery files were preserved.")


def startup_line(process, timeout=8):
    deadline = time.monotonic() + timeout
    output = bytearray()
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))
        if not ready:
            break
        chunk = os.read(process.stdout.fileno(), 4096)
        if not chunk:
            raise RuntimeError("Exercise exited before reporting an active session.")
        output.extend(chunk)
        if len(output) > 16384:
            raise RuntimeError("Unexpectedly large exercise startup response.")
        if b"\n" in output:
            return bytes(output).split(b"\n", 1)[0].decode("utf-8", errors="replace")
    raise RuntimeError("Exercise startup timed out.")


def require_owned_mute(state, initial):
    record = json.loads((state / "recovery.json").read_text())
    if record.get("originalVolume") != initial or alert() != 0:
        raise RuntimeError("The exercise did not establish a journaled mute with the expected baseline.")


def exercise(seconds, states, children):
    state = pathlib.Path(tempfile.mkdtemp(prefix="utilipilled-live-"))
    states.append(state)
    process = subprocess.Popen(
        [str(EXE), "--exercise-session", str(seconds), "--state-dir", str(state)],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    children.append(process)
    if "Exercise active" not in startup_line(process):
        raise RuntimeError("Unexpected exercise startup response.")
    return process, state


def complete(process, timeout=12):
    output, errors = process.communicate(timeout=timeout)
    if process.returncode != 0:
        raise RuntimeError(f"Exercise failed ({process.returncode}): {errors.decode(errors='replace')}")


def cleanup(children, states):
    for process in children:
        if process.poll() is None:
            try:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=4)
            except (ProcessLookupError, subprocess.TimeoutExpired) as error:
                print(f"Exercise cleanup needs attention: {error}")
    # Give each independent guardian time to restore. Explicit recovery retries
    # obey the app's compare-before-restore policy, preserving nonzero user changes.
    for state in states:
        if (state / "recovery.json").exists():
            try:
                wait_for(lambda: not (state / "recovery.json").exists(), timeout=3)
            except RuntimeError:
                try:
                    subprocess.run([str(EXE), "--recover", "--state-dir", str(state)],
                                   stdin=subprocess.DEVNULL, capture_output=True, timeout=8, check=False)
                except (OSError, subprocess.TimeoutExpired) as error:
                    print(f"Recovery needs attention at {state}: {error}")
        if (state / "recovery.json").exists():
            print(f"Recovery still needed: {state}")
            continue
        # Do not delete a directory while a recovery helper still owns its lock.
        try:
            fd = os.open(state / "instance.lock", os.O_RDWR | os.O_NOFOLLOW)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                shutil.rmtree(state)
            finally:
                os.close(fd)
        except (FileNotFoundError, BlockingIOError):
            pass
        except OSError as error:
            print(f"Test directory preserved at {state}: {error}")


def main():
    if not EXE.is_file():
        raise RuntimeError("Build Utilipilled before running live checks.")
    with production_lock():
        original = settings()
        initial = require_audible_baseline(original)
        results, children, states = {}, [], []
        pending_override = None
        try:
            for mode in ("normal", "crash", "helper-crash", "user-override"):
                if alert() != initial:
                    raise RuntimeError("Alert volume changed outside the test; stopping without replacing it.")
                process, state = exercise(3, states, children)
                require_owned_mute(state, initial)
                muted = settings()
                for field in ("output volume", "input volume", "output muted"):
                    if muted[field] != original[field]:
                        raise RuntimeError(f"{field} changed during the exercise.")
                if mode == "crash":
                    process.kill()
                    process.wait(timeout=3)
                    wait_for(lambda: alert() == initial and not (state / "recovery.json").exists())
                elif mode == "helper-crash":
                    helpers = subprocess.check_output(['pgrep', '-P', str(process.pid)], text=True).split()
                    if len(helpers) != 1:
                        raise RuntimeError("Expected exactly one persistent audio helper.")
                    os.kill(int(helpers[0]), signal.SIGKILL)
                    complete(process)
                    if alert() != initial:
                        raise RuntimeError("Helper restart did not restore the original alert volume.")
                elif mode == "user-override":
                    pending_override = 71 if initial != 71 else 72
                    script(f"set volume alert volume {pending_override}")
                    complete(process)
                    if alert() != pending_override:
                        raise RuntimeError("Override changed unexpectedly; stopping without replacing it.")
                    script(f"set volume alert volume {initial}")
                    pending_override = None
                else:
                    complete(process)
                    if alert() != initial:
                        raise RuntimeError("Original alert volume was not restored.")
                results[mode] = "PASS"
            # Send a valid write and disappear without waiting for its response.
            # This exercises EOF during an in-flight operation, the old writer race.
            for _ in range(3):
                if alert() != initial:
                    raise RuntimeError("Alert volume changed outside the test.")
                state = pathlib.Path(tempfile.mkdtemp(prefix="utilipilled-inflight-"))
                states.append(state)
                record = state / "recovery.json"
                with record.open('x') as journal:
                    os.fchmod(journal.fileno(), 0o600)
                    json.dump({'version': 1, 'originalVolume': initial}, journal)
                    journal.flush()
                    os.fsync(journal.fileno())
                helper = subprocess.Popen([str(EXE), '--watchdog', '--state-dir', str(state)],
                                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                children.append(helper)
                if startup_line(helper) != 'READY':
                    raise RuntimeError("Helper did not become ready for in-flight recovery test.")
                helper.stdin.write(b'WRITE 0\n')
                helper.stdin.flush()
                helper.stdin.close()
                helper.stdout.close()
                helper.wait(timeout=8)
                if helper.returncode != 0:
                    raise RuntimeError("In-flight recovery helper failed.")
                wait_for(lambda: alert() == initial and not record.exists())
            results['in-flight-write-eof'] = 'PASS'
            process, state = exercise(3, states, children)
            require_owned_mute(state, initial)
            duplicate = subprocess.run([str(EXE), "--recover", "--state-dir", str(state)],
                                       stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
            if duplicate.returncode != 1 or b"already running" not in duplicate.stderr:
                raise RuntimeError("Duplicate-instance protection did not reject recovery.")
            complete(process)
            if alert() != initial:
                raise RuntimeError("Original alert volume was not restored after the lock check.")
            results["duplicate-instance"] = "PASS"
        finally:
            cleanup(children, states)
            # Only undo the explicit nonzero value this test wrote. Never set a
            # residual zero or another observed setting blindly to the old value.
            if pending_override is not None and alert() == pending_override:
                script(f"set volume alert volume {initial}")
        final = settings()
        if final != original:
            raise RuntimeError(f"Settings changed; the current values were preserved: {final}")
        report = {"platform": f"macOS {platform.mac_ver()[0]} {platform.machine()}",
                  "baseline": original, "final": final, "checks": results}
        (BASE / "LIVE-VALIDATION.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
