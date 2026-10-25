#!/usr/bin/env python3
"""Build and run the isolated glass probe on an already booted iOS 26+ simulator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BUILD = ROOT / '.build/GlassProbe'
APP = BUILD / 'GlassProbe.app'
BUNDLE = 'local.aether.glassprobe'


def run(*args, check=True, env=None):
    return subprocess.run(args, check=check, text=True, capture_output=True, env=env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default='booted')
    parser.add_argument('--label', default='ios27')
    parser.add_argument('--appearance', choices=['light', 'dark'], default='light')
    args = parser.parse_args()
    APP.mkdir(parents=True, exist_ok=True)
    results = HERE / 'results'
    results.mkdir(exist_ok=True)
    sdk = run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path').stdout.strip()
    source = ROOT / 'Sources/AetherUI/Glass/GlassUtils.swift'
    source_text = source.read_text()
    start = source_text.index('public final class EffectSettingsContainerView')
    end = source_text.index('// MARK: - UIColor helper', start)
    # Preserve the actual Swift property declarations; no @objc/dynamic is added.
    (BUILD / 'LumaContainer.swift').write_text('import UIKit\n' + source_text[start:end])
    info = {
        'CFBundleExecutable': 'GlassProbe', 'CFBundleIdentifier': BUNDLE,
        'CFBundleName': 'GlassProbe', 'CFBundleVersion': '1',
        'CFBundleShortVersionString': '1.0', 'CFBundlePackageType': 'APPL',
        'MinimumOSVersion': '26.0', 'UILaunchScreen': {}, 'UIDeviceFamily': [1, 2],
        'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False,
            'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [
                {'UISceneConfigurationName': 'Default', 'UISceneDelegateClassName': 'ProbeDelegate'}]}}
    }
    (APP / 'Info.plist').write_bytes(plistlib.dumps(info))
    run('xcrun', '--sdk', 'iphonesimulator', 'clang', '-arch', 'arm64',
        '-mios-simulator-version-min=26.0', '-fobjc-arc', '-c', str(HERE / 'GlassProbe.m'),
        '-o', str(BUILD / 'GlassProbe.o'))
    swift = ['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-target',
             'arm64-apple-ios26.0-simulator', '-sdk', sdk]
    run(*swift, '-module-name', 'GlassProbe', '-parse-as-library', '-emit-object',
        str(BUILD / 'LumaContainer.swift'), '-o', str(BUILD / 'LumaContainer.o'))
    run(*swift, '-framework', 'UIKit', '-framework', 'QuartzCore',
        str(BUILD / 'GlassProbe.o'), str(BUILD / 'LumaContainer.o'), '-o', str(APP / 'GlassProbe'))
    run('codesign', '--force', '--sign', '-', str(APP))
    run('xcrun', 'simctl', 'terminate', args.device, BUNDLE, check=False)
    run('xcrun', 'simctl', 'install', args.device, str(APP))
    container = Path(run('xcrun', 'simctl', 'get_app_container', args.device, BUNDLE, 'data').stdout.strip())
    documents = container / 'Documents'
    names = ['inventory', 'hierarchy', 'objects', 'strings', 'materialization', 'materialization-empty']
    # Remove only this probe's old reports so a crashed run cannot return stale evidence.
    for name in names:
        (documents / f'{name}.json').unlink(missing_ok=True)
    env = dict(os.environ, SIMCTL_CHILD_GLASS_PROBE_APPEARANCE=args.appearance)
    run('xcrun', 'simctl', 'launch', args.device, BUNDLE, env=env)
    deadline = time.monotonic() + 45
    while not all((documents / f'{name}.json').exists() for name in names):
        if time.monotonic() >= deadline:
            raise RuntimeError('Probe did not finish; inspect simulator console. No stale results were collected.')
        time.sleep(0.25)
    for name in names:
        data = json.loads((documents / f'{name}.json').read_text())
        (results / f'{args.label}-{name}.json').write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    # Wait for the one-second materialization demo to settle before the screenshot.
    time.sleep(1.2)
    run('xcrun', 'simctl', 'io', args.device, 'screenshot', str(results / f'{args.label}-grid.png'))
    runtimes = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '-j').stdout)
    metadata = {
        'sdk': sdk, 'xcode': run('xcodebuild', '-version').stdout.strip(),
        'gitHead': run('git', '-C', str(ROOT), 'rev-parse', 'HEAD').stdout.strip(),
        'device': args.device, 'appearance': args.appearance,
        'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'probeSHA256': hashlib.sha256((HERE / 'GlassProbe.m').read_bytes()).hexdigest(),
        'runtimes': [{k: r.get(k) for k in ('name', 'version', 'buildversion', 'bundlePath', 'runtimeRoot')} for r in runtimes['runtimes']],
    }
    (results / f'{args.label}-environment.json').write_text(json.dumps(metadata, indent=2) + '\n')
    run('xcrun', 'simctl', 'terminate', args.device, BUNDLE)
    print(f'Collected {len(names)} JSON reports, screenshot and environment: {results / args.label}')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.stderr or exc.stdout or str(exc))
