"""Offline integration tests against the compiled Windows executable."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EXE = Path(__file__).resolve().parents[1] / 'Release' / 'pCallTelegramApi.exe'


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for source in EXE.parent.iterdir():
            if source.suffix in ('.exe', '.dll'):
                shutil.copy2(source, self.root)
        self.requests = []
        self.reply = {'ok': True, 'result': {}}
        self.status = 200
        self.file_status = 200
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                remaining = int(self.headers['Content-Length'])
                size = remaining
                chunks = []
                while remaining:
                    block = self.rfile.read(min(1024 * 1024, remaining))
                    if not block:
                        raise RuntimeError('Incomplete upload')
                    remaining -= len(block)
                    if size < 1024 * 1024:
                        chunks.append(block)
                owner.requests.append((self.path, size, self.headers['Content-Type'], b''.join(chunks)))
                body = json.dumps(owner.reply).encode()
                self.send_response(owner.file_status if self.path.endswith('/sendDocument') else owner.status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.config = self.root / 'CallTelegram.ini'
        self.config.write_text(
            '[MAIN]\nToken=123:offline-test\nSendChatId=-12345\n'
            f'ApiBaseUrl=http://127.0.0.1:{self.server.server_port}/gateway/\n'
            'ConnectTimeout=2000\nReadTimeout=10000\n', encoding='utf-8')

    def run_cli(self, *args, cwd=None):
        return subprocess.run([str(self.root / EXE.name), *args], cwd=cwd or self.root,
                              capture_output=True, timeout=120)

    def test_custom_api_and_config_beside_executable(self):
        elsewhere = self.root / 'elsewhere'
        elsewhere.mkdir()
        result = self.run_cli('hello & + ? 世界', cwd=elsewhere)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.requests), 1)
        path, _, content_type, body = self.requests[0]
        self.assertEqual(path, '/gateway/bot123:offline-test/sendMessage')
        message = BytesParser(policy=default).parsebytes(
            f'Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n'.encode() + body)
        fields = {p.get_param('name', header='content-disposition'): p.get_payload(decode=True)
                  for p in message.iter_parts()}
        self.assertEqual(fields['chat_id'], b'-12345')
        self.assertEqual(fields['text'].decode('utf-8'), 'hello & + ? 世界')

    def test_upload(self):
        file = self.root / 'sample.bin'
        file.write_bytes(b'\x00file-content\xff')
        result = self.run_cli('attachment', str(file))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.requests), 2)
        self.assertTrue(self.requests[1][0].endswith('/sendDocument'))
        self.assertIn(file.read_bytes(), self.requests[1][3])

    @unittest.skipUnless(os.environ.get('TEST_LARGE_UPLOAD') == '1', 'opt-in 1 GiB upload')
    def test_one_gib_upload(self):
        file = self.root / 'one-gib.bin'
        with file.open('wb') as stream:
            stream.truncate(1024 ** 3)
        result = self.run_cli('large attachment', str(file))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.requests), 2)
        self.assertGreater(self.requests[1][1], 1024 ** 3)
        self.assertLess(self.requests[1][1], 1024 ** 3 + 4096)

    def test_missing_file_sends_nothing(self):
        result = self.run_cli('attachment', str(self.root / 'missing.bin'))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.requests, [])

    def test_api_error_is_failure_and_redacts_token(self):
        self.reply = {'ok': False, 'description': 'Rejected 123:offline-test'}
        result = self.run_cli('hello')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b'123:offline-test', result.stdout + result.stderr)

    def test_http_error_is_failure(self):
        self.status = 413
        self.reply = {'ok': False, 'description': 'Request too large'}
        result = self.run_cli('hello')
        self.assertNotEqual(result.returncode, 0)

    def test_file_failure_after_message_is_failure(self):
        self.file_status = 413
        file = self.root / 'sample.bin'
        file.write_bytes(b'document')
        result = self.run_cli('attachment', str(file))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.requests), 2)

    def test_missing_config_is_failure(self):
        self.config.unlink()
        self.assertNotEqual(self.run_cli('hello').returncode, 0)
        self.assertEqual(self.requests, [])

    def test_invalid_timeout_is_failure(self):
        self.config.write_text(self.config.read_text().replace('ReadTimeout=10000', 'ReadTimeout=0'))
        self.assertNotEqual(self.run_cli('hello').returncode, 0)
        self.assertEqual(self.requests, [])

    def test_invalid_url_is_failure(self):
        self.config.write_text(self.config.read_text().replace('http://', 'ftp://'))
        self.assertNotEqual(self.run_cli('hello').returncode, 0)
        self.assertEqual(self.requests, [])

    def test_bad_config_sends_nothing(self):
        self.config.write_text('[MAIN]\nToken=\nSendChatId=\n', encoding='utf-8')
        result = self.run_cli('hello')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.requests, [])

    def test_no_arguments_is_failure(self):
        self.assertNotEqual(self.run_cli().returncode, 0)


if __name__ == '__main__':
    unittest.main()
