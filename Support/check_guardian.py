#!/usr/bin/env python3
"""Read-only helper/protocol checks. Never sends a valid WRITE or creates a recovery record."""
import fcntl
import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time

BASE = Path(__file__).resolve().parents[1]
EXE = BASE / 'dist/Utilipilled.app/Contents/MacOS/Utilipilled'


def receive(process, timeout=3):
    result = bytearray()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], max(0, deadline-time.monotonic()))
        if not ready:
            break
        byte = os.read(process.stdout.fileno(), 1)
        if not byte:
            raise AssertionError('Helper closed its response pipe')
        if byte == b'\n':
            return result.decode()
        result.extend(byte)
        if len(result) > 4096:
            raise AssertionError('Oversized response')
    raise AssertionError('Helper response timeout')


def start(directory, children):
    process = subprocess.Popen([str(EXE), '--watchdog', '--state-dir', str(directory)],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    children.append(process)
    return process


def send(process, message):
    process.stdin.write(message.encode() + b'\n')
    process.stdin.flush()


def volume(process):
    send(process, 'READ')
    response = receive(process)
    assert response.startswith('OK '), response
    assert 0 <= int(response[3:]) <= 100


def close(process):
    process.stdin.close()
    process.stdout.close()
    return process.wait(timeout=4)


def main():
    results, children = {}, []
    try:
        with tempfile.TemporaryDirectory(prefix='utilipilled-readonly-') as raw:
            directory = Path(raw)
            process = start(directory, children)
            assert receive(process) == 'READY'
            start_time = time.monotonic()
            for _ in range(100):
                volume(process)
            elapsed = time.monotonic() - start_time
            results['100_read_requests_seconds'] = round(elapsed, 4)
            descendants = subprocess.run(['pgrep', '-P', str(process.pid)], capture_output=True)
            assert descendants.returncode == 1 and not descendants.stdout, 'Unexpected per-read child process'
            results['no_per_read_child_processes'] = 'PASS'
            for invalid in ('WRITE -1', 'WRITE 101', 'WRITE 0; anything', 'BOGUS'):
                send(process, invalid)
                assert receive(process).startswith('ERROR ')
            volume(process)
            results['bounded_integer_only_commands'] = 'PASS'
            duplicate = start(directory, children)
            assert duplicate.wait(timeout=3) == 1
            results['exclusive_guardian_lock'] = 'PASS'
            # Simulate a replacement parent winning the parent lock before EOF.
            with (directory/'instance.lock').open('a+b') as instance:
                os.chmod(directory/'instance.lock', 0o600)
                fcntl.flock(instance, fcntl.LOCK_EX | fcntl.LOCK_NB)
                process.stdin.close()
                process.stdout.close()
                replacement = start(directory, children)
                assert receive(replacement) == 'READY'
                assert process.wait(timeout=3) == 1
                volume(replacement)
                assert close(replacement) == 1
            results['relaunch_lock_handoff_without_deadlock'] = 'PASS'
            assert not (directory/'recovery.json').exists()
        for mode, payload in [('partial_frame', b'REA'), ('oversized_frame', b'X' * 5000)]:
            with tempfile.TemporaryDirectory(prefix='utilipilled-readonly-') as raw:
                process = start(Path(raw), children)
                assert receive(process) == 'READY'
                process.stdin.write(payload)
                process.stdin.flush()
                assert close(process) == 0
                assert not (Path(raw)/'recovery.json').exists()
                results[mode] = 'PASS'
        with tempfile.TemporaryDirectory(prefix='utilipilled-readonly-') as raw:
            process = start(Path(raw), children)
            assert receive(process) == 'READY'
            send(process, 'READ')
            # Parent disappears without receiving the in-flight response.
            assert close(process) == 0
            assert not (Path(raw)/'recovery.json').exists()
            results['broken_response_pipe_and_eof'] = 'PASS'
    finally:
        for child in children:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=3)
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
