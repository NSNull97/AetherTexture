#!/usr/bin/env python3
"""Compare observed metadata and matched probe cases; does not infer API availability."""
import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESULTS = HERE / 'results'


def read(label, kind):
    return json.loads((RESULTS / f'{label}-{kind}.json').read_text())


def diff_mapping(old, new):
    return {k: {'before': old.get(k), 'after': new.get(k)}
            for k in sorted(old.keys() | new.keys()) if old.get(k) != new.get(k)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', default='ios26', nargs='?')
    parser.add_argument('after', default='ios27', nargs='?')
    args = parser.parse_args()
    old_inv, new_inv = read(args.before, 'inventory'), read(args.after, 'inventory')
    old, new = [{c['name']: c for c in inv['classes']} for inv in [old_inv, new_inv]]
    changed = {}
    for name in sorted(old.keys() & new.keys()):
        delta = {}
        for kind in ['instanceMethods', 'classMethods']:
            a, b = [{m['selector']: m['encoding'] for m in c[kind]} for c in [old[name], new[name]]]
            if a != b:
                delta[kind] = diff_mapping(a, b)
        a, b = [{p['name']: p['attributes'] for p in c['properties']} for c in [old[name], new[name]]]
        if a != b:
            delta['properties'] = diff_mapping(a, b)
        if delta:
            changed[name] = delta
    osum, nsum = read(args.before, 'summary'), read(args.after, 'summary')
    ob, nb = read(args.before, 'objects'), read(args.after, 'objects')
    report = {
        'before': old_inv['os'], 'after': new_inv['os'],
        'note': 'Presence in these loaded processes is observed evidence, not an exhaustive introduction/removal history. Both apps are built with SDK 27 and deployment target 26.',
        'classesOnlyBefore': sorted(old.keys() - new.keys()),
        'classesOnlyAfter': sorted(new.keys() - old.keys()),
        'changedClasses': changed,
        'filterTypesOnlyBefore': sorted(set(ob['CAFilter.types']) - set(nb['CAFilter.types'])),
        'filterTypesOnlyAfter': sorted(set(nb['CAFilter.types']) - set(ob['CAFilter.types'])),
        'systemTintAmount': [ob.get('systemTintAmount'), nb.get('systemTintAmount')],
        'aetherStyleComparison': [ob.get('aetherStyleComparison'), nb.get('aetherStyleComparison')],
        'sampleChanges': {name: diff_mapping(osum['samples'][name], nsum['samples'][name]) for name in osum['samples'].keys() & nsum['samples'].keys()},
    }
    out = RESULTS / f'{args.before}-to-{args.after}-diff.json'
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(out)
    print('Filter additions:', report['filterTypesOnlyAfter'])
    print('Filter removals:', report['filterTypesOnlyBefore'])
    for name in ['UIGlassEffect', '_UIViewGlass', '_UIViewGlassGroup', 'CASDFLayer', 'CASDFGlassDisplacementEffect', 'CASDFKeyFillHighlightEffect', '_UILiquidLensView', '_UIFlexInteraction']:
        print(name, json.dumps(changed.get(name, {}), ensure_ascii=False))


if __name__ == '__main__':
    main()
