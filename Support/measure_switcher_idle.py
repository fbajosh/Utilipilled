#!/usr/bin/env python3
"""Sample one explicitly selected local lab process; no application interaction."""
import argparse
import json
import platform
import subprocess
import time
from pathlib import Path


def cpu_seconds(value):
    days = 0
    if '-' in value:
        day, value = value.split('-', 1)
        days = int(day)
    seconds = 0.0
    for field in value.split(':'):
        seconds = seconds * 60 + float(field)
    return days * 86400 + seconds


def sample(pid):
    value = subprocess.check_output(['ps', '-p', str(pid), '-o', 'time=,rss='], text=True).strip().split()
    if len(value) != 2:
        raise RuntimeError('Selected process is no longer running')
    return {'elapsed': time.monotonic(), 'cpu_seconds': cpu_seconds(value[0]), 'rss_bytes': int(value[1]) * 1024}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--label', choices=['disabled', 'enabled'], required=True)
    parser.add_argument('--duration', type=float, default=300)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.pid <= 0 or args.duration <= 0:
        parser.error('pid and duration must be positive')
    samples = [sample(args.pid)]
    deadline = samples[0]['elapsed'] + args.duration
    while time.monotonic() < deadline:
        time.sleep(min(1, max(0, deadline - time.monotonic())))
        samples.append(sample(args.pid))
    elapsed = samples[-1]['elapsed'] - samples[0]['elapsed']
    data = {
        'schema': 1, 'label': args.label, 'pid': args.pid, 'os': platform.mac_ver()[0],
        'duration_seconds': elapsed,
        'average_cpu_percent': (samples[-1]['cpu_seconds'] - samples[0]['cpu_seconds']) / elapsed * 100,
        'rss_mean_bytes': sum(x['rss_bytes'] for x in samples) / len(samples),
        'rss_min_bytes': min(x['rss_bytes'] for x in samples),
        'rss_max_bytes': max(x['rss_bytes'] for x in samples),
        'samples': samples,
        'limitations': 'RSS from ps; includes lab UI/diagnostics. CPU resolution 0.01 seconds. No native latency comparison.',
    }
    args.output.write_text(json.dumps(data, indent=2) + '\n')
    print(json.dumps({key: value for key, value in data.items() if key != 'samples'}, indent=2))


if __name__ == '__main__':
    main()
