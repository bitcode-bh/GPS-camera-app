#!/usr/bin/env python3
"""Reconcile the selected Gradle runtime graph with licence/NOTICE material."""
import argparse
import collections
import hashlib
import io
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile


def coordinates(text):
    selected = set()
    for line in text.splitlines():
        if line.rstrip().endswith('(c)'):
            continue
        match = re.search(r'(?:\+---|\\---) ([\w.\-]+):([\w.\-]+):(.+)', line)
        if not match:
            continue
        group, artifact, tail = match.groups()
        version = tail.rsplit(' -> ', 1)[-1].split()[0]
        if version.startswith('{'):
            continue
        if ':' in version:
            group, artifact, version = version.split(':', 2)
        selected.add((group, artifact, version))
    return selected


def embedded_notices(data):
    result = []
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for name in sorted(archive.namelist()):
            if re.search(r'(^|/)(LICENSE|NOTICE|COPYING)(\.|$)', name, re.I):
                result.append((name, archive.read(name).decode('utf-8', errors='replace')))
            elif name == 'classes.jar':
                result.extend((f'classes.jar/{path}', text)
                              for path, text in embedded_notices(archive.read(name)))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--graph', required=True, type=Path)
    parser.add_argument('--gradle-cache', required=True, type=Path)
    parser.add_argument('--flutter-sdk', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = root / 'assets/legal'
    apache = (output / 'Apache-2.0.txt').read_text()
    libyuv = (output / 'libyuv-BSD-3-Clause.txt').read_text()
    assert 'END OF TERMS AND CONDITIONS' in apache
    assert 'Copyright 2011 The LibYuv Project Authors' in libyuv
    namespace = {'m': 'http://maven.apache.org/POM/4.0.0'}
    groups = collections.defaultdict(set)
    components = []
    resolved = coordinates(args.graph.read_text())
    assert len(resolved) > 50, 'Expected the full resolved release runtime graph'
    cache = args.gradle_cache / 'caches/modules-2/files-2.1'

    def licences(pom_path, visited=None):
        visited = set() if visited is None else visited
        if pom_path in visited:
            return []
        visited.add(pom_path)
        xml = ET.parse(pom_path).getroot()
        names = [node.findtext('m:name', default='', namespaces=namespace)
                 for node in xml.findall('m:licenses/m:license', namespace)]
        if names:
            return names
        parent = xml.find('m:parent', namespace)
        if parent is None:
            return []
        parent_dir = cache.joinpath(*(parent.findtext(f'm:{field}', default='', namespaces=namespace)
                                      for field in ['groupId', 'artifactId', 'version']))
        parents = list(parent_dir.glob('*/*.pom'))
        return licences(parents[0], visited) if parents else []

    for group, artifact, version in sorted(resolved):
        coordinate = f'{group}:{artifact}:{version}'
        folder = cache / group / artifact / version
        poms = list(folder.glob('*/*.pom'))
        names = licences(poms[0]) if poms else []
        if not names and (group, artifact, version) in {
            ('androidx.emoji2', 'emoji2', '1.2.0'), ('javax.inject', 'javax.inject', '1'),
            ('org.jetbrains', 'annotations', '23.0.0'),
        }:
            names = ['Apache-2.0 (verified upstream; see docs/publishing/third-party-notices.md)']
        if group == 'io.flutter':
            names = ['Flutter BSD and composite engine notices']
            groups[(args.flutter_sdk / 'LICENSE').read_text()].add(coordinate)
            groups[(args.flutter_sdk / 'bin/cache/pkg/sky_engine/LICENSE').read_text()].add(coordinate)
        else:
            assert names and all('apache' in n.lower() or 'bsd-3-clause' in n.lower()
                                 for n in names), f'Review licence before shipping: {coordinate}: {names}'
            if any('apache' in n.lower() for n in names):
                groups[apache].add(coordinate)
            if any('bsd-3-clause' in n.lower() for n in names):
                assert (group, artifact) == ('androidx.camera', 'camera-core'), coordinate
                groups[libyuv].add(coordinate + ' / libyuv')
        artifacts = sorted(p for p in folder.glob('*/*') if p.suffix in {'.jar', '.aar'}
                           and not p.name.endswith(('-sources.jar', '-javadoc.jar')))
        retained = []
        for binary in artifacts:
            for path, text in embedded_notices(binary.read_bytes()):
                groups[text].add(coordinate)
                retained.append(path)
        components.append({'coordinate': coordinate, 'licences': names,
                           'retained_notice_entries': sorted(set(retained)),
                           'artifact_present': bool(artifacts)})
    entries = [{'packages': sorted(packages), 'text': text}
               for text, packages in sorted(groups.items(), key=lambda x: hashlib.sha256(x[0].encode()).hexdigest())]
    (output / 'android-notices.json').write_text(json.dumps(entries, ensure_ascii=False, indent=2) + '\n')
    (output / 'android-components.json').write_text(json.dumps(components, ensure_ascii=False, indent=2) + '\n')
    assert all(any(c['coordinate'] in p for entry in entries for p in entry['packages']) for c in components)
    print(f'{len(components)} runtime coordinates; {len(entries)} distinct licence/notice texts retained.')


if __name__ == '__main__':
    main()
