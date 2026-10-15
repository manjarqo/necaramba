#!/usr/bin/env python3
"""Build/run the pure Swift policy comparison without app permissions or user data."""
import pathlib, subprocess, tempfile, sys
root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='necaramba-policy-benchmark-') as folder:
    binary = pathlib.Path(folder) / 'benchmark'
    metrics = '--metrics' in sys.argv[1:]
    sources = [root / 'Sources/NecarambaMac/Input/InputPerformanceMetrics.swift'] if metrics else sorted((root / 'Sources/NecarambaCore').rglob('*.swift'))
    entry = 'MetricsBenchmark.swift' if metrics else 'PolicyBenchmark.swift'
    subprocess.run(['swiftc', '-O', '-o', str(binary), *map(str, sources),
                    str(root / 'Tools/Performance' / entry)], check=True)
    subprocess.run([str(binary)], check=True)
