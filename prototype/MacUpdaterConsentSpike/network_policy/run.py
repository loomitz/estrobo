#!/usr/bin/env python3
"""Foundation positive controls, separate from the actual Sparkle installer test."""
import http.server
import json
import os
import pathlib
import subprocess
import tempfile
import threading

root = pathlib.Path(__file__).resolve().parent
requests = []


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append(self.path)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ORIGIN')

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='estrobo-foundation-policy-') as temporary:
        binary = pathlib.Path(temporary) / 'levers'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(root / 'levers.m'), '-o', str(binary)], check=True, env=dict(os.environ))
        results = {}
        for mode in ['default-protocol', 'shared-protocol', 'explicit-protocol', 'default-cache', 'cache-only']:
            result = subprocess.run([str(binary), mode, f'http://127.0.0.1:{server.server_port}/{mode}'], capture_output=True, text=True, timeout=10)
            results[mode] = {'output': result.stderr, 'exit': result.returncode}
        results['origin_requests'] = requests
        assert 'body=ORIGIN' in results['default-protocol']['output']
        assert 'error=-1002' in results['shared-protocol']['output']
        assert 'error=-1002' in results['explicit-protocol']['output']
        assert 'body=ORIGIN' in results['default-cache']['output']
        assert 'body=CACHE_INJECTION' in results['cache-only']['output']
        assert requests == ['/default-protocol', '/default-cache']
        print(json.dumps(results, indent=2))
finally:
    server.shutdown()
