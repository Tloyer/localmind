#!/usr/bin/env python3
"""Embed UI assets so HTTP requests never hydrate project files via File Provider."""
import base64
from pathlib import Path
import zlib
root = Path(__file__).resolve().parents[1]
p = root / 'localmind/server.py'
s = p.read_text()
start = s.index('# BEGIN PACKAGED UI')
end = s.index('# END PACKAGED UI', start) + len('# END PACKAGED UI')
assets = {'/': ('text/html', 'index.html'), '/index.html': ('text/html', 'index.html'), '/app.js': ('text/javascript', 'app.js'), '/style.css': ('text/css', 'style.css')}
lines = ['# BEGIN PACKAGED UI (refresh with scripts/package-ui.py)', 'import zlib', 'PACKAGED_UI = {']
for url, (mime, name) in assets.items():
    encoded = base64.b64encode(zlib.compress((root / 'frontend' / name).read_bytes())).decode()
    lines.append(f'    {url!r}: ({(mime + "; charset=utf-8")!r}, zlib.decompress(base64.b64decode({encoded!r}))),')
lines += ['}', '# END PACKAGED UI']
p.write_text(s[:start] + '\n'.join(lines) + s[end:])
