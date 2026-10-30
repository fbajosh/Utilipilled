#!/usr/bin/env python3
"""Update the release fields in a Homebrew cask without downgrading it."""
import argparse
from pathlib import Path
import re


def update_cask(path, version, sha256):
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Expected a stable major.minor.patch version')
    if not re.fullmatch(r'[0-9a-f]{64}', sha256):
        raise ValueError('Expected a lowercase SHA-256 checksum')
    text = path.read_text()
    versions = re.findall(r'^  version "([0-9]+\.[0-9]+\.[0-9]+)"$', text, re.M)
    checksums = re.findall(r'^  sha256 "([0-9a-f]{64})"$', text, re.M)
    if len(versions) != 1 or len(checksums) != 1:
        raise ValueError('Expected exactly one version and checksum in the cask')
    current = versions[0]
    if tuple(map(int, version.split('.'))) < tuple(map(int, current.split('.'))):
        raise ValueError('Refusing to downgrade the cask')
    if version == current:
        if sha256 != checksums[0]:
            raise ValueError('Refusing to replace an existing version with different bytes')
        return False
    text = re.sub(r'^  version "[0-9]+\.[0-9]+\.[0-9]+"$', f'  version "{version}"', text, flags=re.M)
    text = re.sub(r'^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{sha256}"', text, flags=re.M)
    path.write_text(text)
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('version')
    parser.add_argument('sha256')
    args = parser.parse_args()
    update_cask(args.path, args.version, args.sha256)
