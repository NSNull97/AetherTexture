#!/usr/bin/env python3
"""Generate searchable catalogs and compact summaries from probe evidence."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
RESULTS = HERE / 'results'


def walk(layer):
    yield layer
    for child in layer['sublayers']:
        yield from walk(child)


def clean(value):
    if isinstance(value, str):
        return re.sub(r'0x[0-9a-fA-F]+', '<address>', value)
    if isinstance(value, list):
        return [clean(v) for v in value]
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items() if k not in ['description']}
    return value


def summarize(label):
    inventory, hierarchy, objects, strings, motion = [
        json.loads((RESULTS / f'{label}-{name}.json').read_text())
        for name in ['inventory', 'hierarchy', 'objects', 'strings', 'materialization']]
    layers = list(walk(hierarchy['window']['layers']))
    filters = [f for layer in layers for f in layer['filters']]
    samples = {}
    for name, sample in hierarchy.items():
        if name == 'window':
            continue
        group = sample.get('renderContainer', sample['layers'])
        samples[name] = {
            'rootLayer': sample['layers']['class'], 'renderContainer': group['class'],
            'filters': [{'type': f.get('type'), 'inputs': clean(f.get('observedInputs', {}))}
                        for layer in walk(group) for f in layer['filters']
                        if f.get('type') in ['glassBackground', 'glassForeground']],
            'effects': [clean(layer['effectProperties']) for layer in walk(group) if layer.get('effectProperties')],
            'setter': {k: sample['configuration'][k] for k in ['setter', 'value', 'status'] if k in sample['configuration']},
        }
    baseline = samples['regular']['filters']
    for name, sample in samples.items():
        sample['sameGlassFilterInputsAsRegular'] = sample['filters'] == baseline
    summary = {
        'os': inventory['os'], 'scannedClassCount': inventory['totalClassCount'],
        'selectedClassCount': len(inventory['classes']), 'selectedProtocolCount': len(inventory.get('protocols', [])),
        'selectorHitCount': len(inventory['selectorHits']),
        'imageStringCounts': {Path(k).name: len(v) for k, v in strings.items()},
        'layerCounts': dict(Counter(x['class'] for x in layers)),
        'filterCounts': dict(Counter(f.get('type', '?') for f in filters)),
        'observedInputKeysByFilter': {name: sorted({key for f in filters if f.get('type') == name for key in f.get('observedInputs', {})}) for name in ['glassBackground', 'glassForeground']},
        'animationKeyPaths': sorted({a.get('keyPath', a['key']) for l in walk(motion) for a in l['animations']}),
        'aetherLumaContainer': objects.get('aetherLumaContainer'),
        'systemTintAmount': objects.get('systemTintAmount'), 'samples': samples,
    }
    empty_path = RESULTS / f'{label}-materialization-empty.json'
    if empty_path.exists():
        empty = json.loads(empty_path.read_text())
        summary['emptyEffectAnimationKeyPaths'] = sorted({a.get('keyPath', a['key']) for l in walk(empty) for a in l['animations']})
    (RESULTS / f'{label}-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    lines = [f'# Runtime catalog: {label}', '',
             f"{inventory['os']}. Scanned {inventory['totalClassCount']} loaded Objective-C classes; selected {len(inventory['classes'])} by the documented name pattern.", '',
             'This is a metadata inventory, not a compatibility guarantee. Name matches include unrelated classes. Method encodings preserve the observed ABI. Empty Swift method tables do not imply an absent Swift API.', '',
             '## Classes', '', '| Class | Superclass | Instance / class methods |', '|---|---|---|']
    for c in inventory['classes']:
        lines.append(f"| `{c['name']}` | `{c['superclass']}` | {len(c['instanceMethods'])} / {len(c['classMethods'])} |")
    for c in inventory['classes']:
        lines += ['', f"## {c['name']}", '', f"Runtime name: `{c.get('runtimeName', c['name'])}`", '', f"Image: `{Path(c['image']).name}`", '', '```text']
        lines += [f"property {p['name']} : {p['attributes']}" for p in c['properties']]
        lines += [f"- {m['selector']}  {m['encoding']}" for m in c['instanceMethods']]
        lines += [f"+ {m['selector']}  {m['encoding']}" for m in c['classMethods']]
        lines += ['```']
    lines += ['', '## Protocols']
    for p in inventory.get('protocols', []):
        lines += ['', f"### {p['name']}", '', '```text']
        lines += [f"{'-' if m['instance'] else '+'} {m['selector']}  {m['encoding']}  {'required' if m['required'] else 'optional'}" for m in p['methods']]
        lines += ['```']
    (HERE / f'RuntimeCatalog-{label}.md').write_text('\n'.join(lines) + '\n')
    print(label, {k: summary[k] for k in ['scannedClassCount', 'selectedClassCount', 'selectedProtocolCount', 'selectorHitCount']})
    return summary


def sdk_index():
    sdk = Path(subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip())
    hits = []
    for framework in ['UIKit', 'SwiftUI', 'SwiftUICore', 'QuartzCore']:
        root = sdk / 'System/Library/Frameworks' / f'{framework}.framework'
        for path in sorted(root.rglob('*')):
            if path.suffix not in ['.h', '.swiftinterface']:
                continue
            if path.suffix == '.swiftinterface' and path.name != 'arm64-apple-ios-simulator.swiftinterface':
                continue
            lines = path.read_text().splitlines()
            for i, line in enumerate(lines):
                if re.search(r'glass|liquid|scrolledge|backgroundExtension|UICorner|cornerConfiguration|containerConcentric|sharedBackground|preferredImageVisibility', line, re.I):
                    hits.append({'file': str(path.relative_to(sdk)), 'line': i + 1, 'text': line.strip(), 'preceding': lines[max(0, i-3):i]})
    (RESULTS / 'sdk27-api-index.json').write_text(json.dumps({'sdk': str(sdk), 'hits': hits}, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('labels', nargs='*', default=['ios27', 'ios27-dark'])
    args = parser.parse_args()
    for label in args.labels:
        summarize(label)
    sdk_index()
