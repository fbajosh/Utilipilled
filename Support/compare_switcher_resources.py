#!/usr/bin/env python3
"""Compare one matched pair of isolated-lab idle samples, not release acceptance."""
import argparse
import json
from pathlib import Path


def compare(disabled, enabled):
    if disabled.get('schema') != 1 or enabled.get('schema') != 1:
        raise ValueError('Unsupported resource sample schema')
    if disabled.get('label') != 'disabled' or enabled.get('label') != 'enabled':
        raise ValueError('Provide disabled and enabled samples in the correct order')
    if disabled.get('pid') != enabled.get('pid') or disabled.get('os') != enabled.get('os'):
        raise ValueError('Samples must use the same process and OS')
    if min(disabled['duration_seconds'], enabled['duration_seconds']) < 300:
        raise ValueError('Each sample must cover at least five minutes')
    cpu = enabled['average_cpu_percent'] - disabled['average_cpu_percent']
    rss = enabled['rss_mean_bytes'] - disabled['rss_mean_bytes']
    return {
        'scope': 'One sequential pair from the isolated lab; not production release acceptance',
        'enabled_cpu_percent': enabled['average_cpu_percent'],
        'disabled_cpu_percent': disabled['average_cpu_percent'],
        'incremental_cpu_percentage_points': cpu,
        'enabled_mean_rss_bytes': enabled['rss_mean_bytes'],
        'disabled_mean_rss_bytes': disabled['rss_mean_bytes'],
        'incremental_mean_rss_bytes': rss,
        'incremental_mean_rss_MiB': rss / 1048576,
        'observed_increment_below_initial_targets': cpu < 0.1 and rss <= 25000000,
        'limitations': 'Sequential order, cache warming and paging can affect signed differences. Repeat in production and counterbalance order before acceptance.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--disabled', type=Path, required=True)
    parser.add_argument('--enabled', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(compare(json.loads(args.disabled.read_text()), json.loads(args.enabled.read_text())), indent=2))


if __name__ == '__main__':
    main()
