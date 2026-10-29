#!/usr/bin/env bash
# Keep OpenWrt's per-task timing visible in quiet builds.
set -euo pipefail

python3 - "$1/scripts/time.pl" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
original = '\tprintf STDOUT "%s#%.2f#%.2f#%.2f\\n",'
replacement = '''\t# wrt_release: route timing through the quiet-build progress descriptor.
\tmy $timing_output;
\tif (!open($timing_output, '>&', 8)) {
\t\t$timing_output = \\*STDOUT;
\t}
\tprintf {$timing_output} "%s#%.2f#%.2f#%.2f\\n",'''

source = path.read_text()
if source.count(replacement) == 1:
    sys.exit(0)
if source.count(original) != 1 or 'wrt_release: route timing' in source:
    sys.exit(f'[build-timing] Unsupported upstream timing implementation: {path}')
path.write_text(source.replace(original, replacement, 1))
print('[build-timing] Per-task timing enabled for quiet builds.')
PY
