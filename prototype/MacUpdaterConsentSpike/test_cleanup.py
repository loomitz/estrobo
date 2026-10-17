#!/usr/bin/env python3
"""Public runner context: failures must preserve evidence and remove its secrets."""
import http.server
import importlib.util
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.request

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location('consent_runner', pathlib.Path(__file__).with_name('run.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'fixture')

    def log_message(self, *args):
        pass


class CleanupContractTests(unittest.TestCase):
    def test_failed_process_termination_still_removes_secrets_closes_server_and_reports_failure(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-cleanup-test-') as temporary:
            output = pathlib.Path(temporary) / 'evidence'
            fixture = runner.FixtureRun(output)
            process = None
            try:
                process = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
                with patch.object(process, 'terminate', side_effect=OSError('injected terminate failure')):
                    with self.assertRaisesRegex(RuntimeError, 'cleanup'):
                        with fixture:
                            (fixture.secrets / 'fixture-private-key').write_text('ephemeral test fixture')
                            server = fixture.start_server(Handler)
                            address = server.server_address
                            self.assertEqual(urllib.request.urlopen(f'http://127.0.0.1:{address[1]}').read(), b'fixture')
                            fixture.process = process
                self.assertIsNotNone(process.poll())
                self.assertFalse(fixture.secrets.exists())
                with self.assertRaises(OSError):
                    socket.create_connection(address, timeout=.2)
                result = json.loads((output / 'results.json').read_text())
                self.assertFalse(result['passed'])
                self.assertIn('injected terminate failure', '\n'.join(result['cleanup_errors']))
                self.assertTrue((output / 'events.log').exists())
            finally:
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait(timeout=3)


    def test_partial_server_setup_failure_releases_bound_socket_and_preserves_failure_evidence(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-cleanup-test-') as temporary:
            output = pathlib.Path(temporary) / 'evidence'
            fixture = runner.FixtureRun(output)
            addresses = []
            real_server = runner.http.server.ThreadingHTTPServer

            def capture_server(*args, **kwargs):
                server = real_server(*args, **kwargs)
                addresses.append(server.server_address)
                return server

            with self.assertRaisesRegex(RuntimeError, 'injected server startup failure'):
                with fixture:
                    (fixture.secrets / 'fixture-private-key').write_text('ephemeral test fixture')
                    first_server = fixture.start_server(Handler)
                    addresses.append(first_server.server_address)
                    with patch.object(runner.http.server, 'ThreadingHTTPServer', side_effect=capture_server):
                        with patch.object(runner.threading.Thread, 'start', side_effect=RuntimeError('injected server startup failure')):
                            fixture.start_server(Handler)
            self.assertFalse(fixture.secrets.exists())
            for address in addresses:
                with self.assertRaises(OSError):
                    socket.create_connection(address, timeout=.2)
            result = json.loads((output / 'results.json').read_text())
            self.assertFalse(result['passed'])
            self.assertIn('injected server startup failure', result['failure'])

    def test_secret_directory_allocation_failure_still_publishes_failed_setup_result(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-cleanup-test-') as temporary:
            output = pathlib.Path(temporary) / 'evidence'
            fixture = runner.FixtureRun(output)
            real_mkdtemp = runner.tempfile.mkdtemp

            def fail_secret_directory(*args, **kwargs):
                if kwargs.get('prefix') == 'estrobo-consent-fixture-secrets-':
                    raise OSError('injected secrets allocation failure')
                return real_mkdtemp(*args, **kwargs)

            with patch.object(runner.tempfile, 'mkdtemp', side_effect=fail_secret_directory):
                with self.assertRaisesRegex(OSError, 'injected secrets allocation failure'):
                    with fixture:
                        self.fail('failed setup must not enter the fixture body')
            result = json.loads((output / 'results.json').read_text())
            self.assertFalse(result['passed'])
            self.assertIn('injected secrets allocation failure', result['failure'])
            self.assertTrue((output / 'events.log').exists())

    def test_process_timeout_does_not_hide_original_failure_or_leave_secrets(self):
        with tempfile.TemporaryDirectory(prefix='estrobo-cleanup-test-') as temporary:
            output = pathlib.Path(temporary) / 'evidence'
            fixture = runner.FixtureRun(output)
            process = subprocess.Popen([sys.executable, '-c', 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print("ready", flush=True); time.sleep(60)'], stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(process.stdout.readline().strip(), 'ready')
                with self.assertRaisesRegex(RuntimeError, 'injected body failure'):
                    with fixture:
                        (fixture.secrets / 'fixture-private-key').write_text('ephemeral test fixture')
                        fixture.process = process
                        raise RuntimeError('injected body failure')
                self.assertIsNotNone(process.poll())
                self.assertFalse(fixture.secrets.exists())
                result = json.loads((output / 'results.json').read_text())
                self.assertFalse(result['passed'])
                self.assertIn('injected body failure', result['failure'])
                self.assertIn('TimeoutExpired', '\n'.join(result['cleanup_errors']))
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=3)
                process.stdout.close()


if __name__ == '__main__':
    unittest.main()
