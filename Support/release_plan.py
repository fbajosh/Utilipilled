#!/usr/bin/env python3
"""Decide whether a main-branch build or version tag should publish a release."""
import os
from pathlib import Path
import plistlib
import re


def version_tuple(version):
    if not isinstance(version, str) or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Use a stable major.minor.patch version')
    return tuple(map(int, version.split('.')))


def release_plan(version, latest_tag, ref):
    current = version_tuple(version)
    tag = f'v{version}'
    if ref not in ('refs/heads/main', f'refs/tags/{tag}'):
        raise ValueError('Release only from main or a tag matching the app version')
    publish = True
    if latest_tag:
        latest = version_tuple(latest_tag.removeprefix('v'))
        if current < latest:
            raise ValueError('Refusing to release an older version')
        if current == latest:
            if ref != 'refs/heads/main':
                raise ValueError('That version has already been released')
            publish = False
    return {'version': version, 'tag': tag, 'publish': str(publish).lower()}


if __name__ == '__main__':
    info = plistlib.loads(Path('Support/Info.plist').read_bytes())
    plan = release_plan(info['CFBundleShortVersionString'], os.environ['LATEST_TAG'], os.environ['GITHUB_REF'])
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for name, value in plan.items():
            output.write(f'{name}={value}\n')
    print('New version: publish after tests.' if plan['publish'] == 'true' else 'Version already published: checks only.')
