#!/usr/bin/env python3
"""Fail before Gradle when the FX merge has duplicate named Android resources."""
from collections import defaultdict
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'adhook/app/src/main/res')
if not root.is_dir():
    raise SystemExit(f'Android resource directory missing: {root}')
seen = defaultdict(list)
for path in sorted(root.rglob('*.xml')):
    if not path.parent.name.startswith('values'):
        continue
    try:
        document = ET.parse(path).getroot()
    except ET.ParseError as error:
        raise SystemExit(f'{path}: invalid Android values XML: {error}')
    if document.tag != 'resources':
        continue
    for node in document:
        if node.tag in {'public', 'eat-comment', 'skip'}:
            continue
        name = node.attrib.get('name')
        resource_type = node.attrib.get('type') if node.tag == 'item' else node.tag
        if name and resource_type:
            seen[(path.parent.name, resource_type, name)].append(path)
duplicates = {key: paths for key, paths in seen.items() if len(paths) > 1}
if duplicates:
    for (qualifier, resource_type, name), paths in sorted(duplicates.items()):
        print(f'DUPLICATE_RESOURCE {qualifier}/{resource_type}/{name}: ' + ', '.join(map(str, paths)), file=sys.stderr)
    raise SystemExit(1)
print(f'PASS: {len(seen)} unique named Android resources across {root}')
