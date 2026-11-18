#!/usr/bin/env python3
"""Summarize lab timestamps; these are not physical display latency measurements."""
import argparse
import collections
import json
import math
from pathlib import Path


def percentiles(values):
    values = sorted(values)
    if not values:
        return {'n': 0, 'p50_ms': None, 'p95_ms': None, 'p99_ms': None}
    return {'n': len(values), **{f'p{p}_ms': values[max(0, math.ceil(len(values) * p / 100) - 1)] for p in [50, 95, 99]}}


def analyze(data):
    if data.get('schema') != 1 or not isinstance(data.get('events'), list):
        raise ValueError('Unsupported measurement format')
    sessions = collections.defaultdict(list)
    for event in data['events']:
        if not isinstance(event.get('session'), int) or not isinstance(event.get('time'), int):
            raise ValueError('Events require integer session and timestamp fields')
        sessions[event['session']].append(event)
    durations = collections.defaultdict(list)
    for events in sessions.values():
        events.sort(key=lambda e: e['time'])
        start = commit = selection = None
        for event in events:
            kind, stamp = event['kind'], event['time']
            if kind == 'invocation':
                start = stamp
            elif kind == 'selection':
                selection = stamp
            elif kind == 'presentation' and start is not None:
                durations['invocation_to_AppKit_presentation'].append((stamp - start) / 1e6)
            elif kind == 'render' and selection is not None:
                durations['selection_to_AppKit_draw'].append((stamp - selection) / 1e6)
                selection = None
            elif kind in ['commit', 'drop']:
                commit = stamp
            elif kind == 'activationConfirmed' and commit is not None:
                durations['commit_to_observed_frontmost'].append((stamp - commit) / 1e6)
    counts = collections.Counter(event['kind'] for event in data['events'])
    return {
        'measurement': 'AppKit processing and workspace notifications; NOT physical input/display latency',
        'counts': dict(counts),
        'latencies': {key: percentiles(durations[key]) for key in [
            'invocation_to_AppKit_presentation', 'selection_to_AppKit_draw', 'commit_to_observed_frontmost']},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    args = parser.parse_args()
    print(json.dumps(analyze(json.loads(args.path.read_text())), indent=2))


if __name__ == '__main__':
    main()
