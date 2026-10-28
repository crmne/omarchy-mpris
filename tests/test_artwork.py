"""Tests for bin/artwork, the helper that bounds what album art can cost.

Run with: python3 -m unittest discover -s tests

Qt's Image buffers an http(s) response whole before decoding it, so the
helper is what keeps a cover server from exhausting the shell's memory. These
serve covers from a throwaway server on loopback and check that oversized,
endless, slow, and redirected answers never reach the cache, and that covers
on disk are size-checked rather than copied.
"""

import http.client
import http.server
import importlib.machinery
import importlib.util
import io
import json
import os
import stat
import tempfile
import threading
import time
import unittest
import urllib.parse
from contextlib import redirect_stdout
from unittest import mock

HELPER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "artwork")
spec = importlib.util.spec_from_loader("artwork", importlib.machinery.SourceFileLoader("artwork", HELPER))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

COVER = b"\x89PNG\r\n\x1a\n" + b"\x00" * 200
LIMIT = 4096


class Handler(http.server.BaseHTTPRequestHandler):
    hits = []

    def log_message(self, *args):
        pass

    def do_GET(self):
        Handler.hits.append(self.path)
        route = self.path.split("?")[0]
        if route == "/cover.png":
            self.answer(COVER)
        elif route == "/declared-huge":
            self.send_response(200)
            self.send_header("Content-Length", str(LIMIT + 1))
            self.end_headers()
        elif route == "/endless":
            # No length up front, and more than the limit behind it.
            self.send_response(200)
            self.send_header("Connection", "close")
            self.end_headers()
            try:
                for _ in range(64):
                    self.wfile.write(b"\xff" * 1024)
            except OSError:
                pass
        elif route == "/gzip":
            self.send_response(200)
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", "4")
            self.end_headers()
            self.wfile.write(b"\x1f\x8b\x08\x00")
        elif route == "/slow":
            self.send_response(200)
            self.send_header("Content-Length", "100")
            self.end_headers()
            time.sleep(3)
        elif route == "/to-file":
            self.redirect("file:///etc/passwd")
        elif route == "/to-ftp":
            self.redirect("ftp://127.0.0.1/cover.png")
        elif route == "/to-cover":
            self.redirect("/cover.png")
        elif route == "/missing":
            self.send_error(404)
        else:
            self.answer(b"")

    def answer(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def redirect(self, location):
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()


class Server:
    def __enter__(self):
        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = "http://127.0.0.1:%d" % self.httpd.server_address[1]
        return self

    def __exit__(self, *exc):
        self.httpd.shutdown()
        self.httpd.server_close()


class ArtworkCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = os.path.join(self.tmp.name, "cache", "artwork")
        patches = [mock.patch.object(helper, "CACHE_DIR", self.cache),
                   mock.patch.object(helper, "MAX_ARTWORK_BYTES", LIMIT)]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.addCleanup(self.tmp.cleanup)
        Handler.hits = []
        self.server = Server().__enter__()
        self.addCleanup(self.server.__exit__)

    def url(self, path):
        return self.server.base + path

    def entries(self):
        return sorted(os.listdir(self.cache)) if os.path.isdir(self.cache) else []

    def run_main(self, url, request="3", argv=("--allow-http",)):
        out = io.StringIO()
        env = {"ARTWORK_URL": url, "ARTWORK_REQUEST": request}
        with mock.patch.dict(os.environ, env), redirect_stdout(out):
            code = helper.main(list(argv))
            leaked = [key for key in env if key in os.environ]
        return code, json.loads(out.getvalue()), leaked


class RemoteArtwork(ArtworkCase):
    def test_a_cover_is_downloaded_into_a_private_cache(self):
        source = helper.resolve(self.url("/cover.png"), allow_http=True)
        path = urllib.parse.unquote(urllib.parse.urlsplit(source).path)
        self.assertTrue(source.startswith("file://"))
        self.assertEqual(os.path.dirname(path), self.cache)
        with open(path, "rb") as handle:
            self.assertEqual(handle.read(), COVER)
        self.assertEqual(stat.S_IMODE(os.stat(self.cache).st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode) & 0o077, 0)

    def test_a_cached_cover_is_not_downloaded_again(self):
        first = helper.resolve(self.url("/cover.png"), allow_http=True)
        second = helper.resolve(self.url("/cover.png"), allow_http=True)
        self.assertEqual(first, second)
        self.assertEqual(Handler.hits, ["/cover.png"])

    def test_a_declared_length_over_the_limit_is_refused_before_reading(self):
        with self.assertRaises(helper.TooLarge):
            helper.resolve(self.url("/declared-huge"), allow_http=True)
        self.assertEqual(self.entries(), [])

    def test_a_body_that_runs_past_the_limit_is_cut_off_and_discarded(self):
        # The case Qt cannot handle: no length up front, and no end in sight.
        with self.assertRaises(helper.TooLarge):
            helper.resolve(self.url("/endless"), allow_http=True)
        self.assertEqual(self.entries(), [], "neither the cover nor a partial download is kept")

    def test_a_compressed_body_is_refused(self):
        with self.assertRaises(helper.Blocked):
            helper.resolve(self.url("/gzip"), allow_http=True)
        self.assertEqual(self.entries(), [])

    def test_redirects_are_followed_but_only_to_allowed_schemes(self):
        self.assertTrue(helper.resolve(self.url("/to-cover"), allow_http=True).startswith("file://"))
        with self.assertRaises(helper.Blocked):
            helper.resolve(self.url("/to-ftp"), allow_http=True)
        # urllib refuses this hop itself, before the guard sees it.
        with self.assertRaises((helper.Blocked, helper.urllib.error.HTTPError)):
            helper.resolve(self.url("/to-file"), allow_http=True)
        self.assertEqual(len(self.entries()), 1, "only the cover that was allowed")

    def test_a_redirect_body_is_never_read(self):
        # CPython reads a redirect's body to the end before following it, so
        # an endless one would grow the helper without bound.
        class Endless:
            closed = False
            served = 0

            def read(self, size=-1):
                if self.closed:
                    return b""
                self.served += 1 << 20
                return b"x" * (1 << 20)

            def close(self):
                self.closed = True

        handler = helper.GuardedRedirects()
        handler.parent = mock.Mock()
        body = Endless()
        request = helper.urllib.request.Request("https://example.com/a.png")
        request.timeout = 5
        headers = http.client.HTTPMessage()
        headers["Location"] = "https://example.com/b.png"
        handler.http_error_302(request, body, 302, "Found", headers)
        handler.parent.open.assert_called_once()
        self.assertTrue(body.closed)
        self.assertEqual(body.served, 0)

    def test_plain_http_needs_the_flag(self):
        with self.assertRaises(helper.Blocked):
            helper.resolve(self.url("/cover.png"), allow_http=False)
        self.assertEqual(Handler.hits, [])
        handler = helper.GuardedRedirects()
        with self.assertRaises(helper.Blocked):
            handler.redirect_request(None, None, 302, "", {}, "http://example.com/x")

    def test_urls_that_are_not_plain_http_or_https_are_refused(self):
        for url in ("ftp://example.com/a.png", "data:image/png;base64,AAAA",
                    "https:///no-host.png", "https://example.com/a b.png",
                    "https://example.com\\@evil/", "", "/etc/passwd",
                    "https://example.com/" + "a" * helper.MAX_URL_CHARS):
            with self.assertRaises(helper.Blocked, msg=url):
                helper.resolve(url, allow_http=True)

    def test_the_cache_keeps_only_the_newest_covers(self):
        os.makedirs(self.cache, mode=0o700)
        now = time.time()
        for index in range(5):
            path = os.path.join(self.cache, ("%x" % index) * 64)
            with open(path, "wb") as handle:
                handle.write(b"x" * 10)
            os.utime(path, (now - 100 + index, now - 100 + index))
        stale = os.path.join(self.cache, ".part-old")
        open(stale, "wb").close()
        os.utime(stale, (now - 3600, now - 3600))
        with mock.patch.object(helper, "MAX_CACHE_ENTRIES", 2):
            helper.prune(self.cache, ("1" * 64))
        self.assertEqual(self.entries(), sorted(["1" * 64, "4" * 64]))


class Main(ArtworkCase):
    def test_the_url_comes_from_the_environment_and_does_not_linger(self):
        code, payload, leaked = self.run_main(self.url("/cover.png"), request="7")
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["request"], "7")
        self.assertTrue(payload["source"].startswith("file://" + urllib.parse.quote(self.cache)))
        self.assertEqual(leaked, [])

    def test_failures_are_reported_as_json(self):
        cases = {"/endless": "too_large", "/missing": "http", "/to-ftp": "blocked"}
        for path, expected in cases.items():
            code, payload, _ = self.run_main(self.url(path))
            self.assertEqual((code, payload["ok"], payload["code"]), (1, False, expected), path)
            self.assertEqual(payload["request"], "3")

    def test_a_server_that_stalls_runs_into_the_deadline(self):
        with mock.patch.object(helper, "DEADLINE_SECONDS", 1):
            started = time.monotonic()
            code, payload, _ = self.run_main(self.url("/slow"))
        self.assertLess(time.monotonic() - started, 2.5)
        self.assertEqual(payload["code"], "timeout")
        self.assertEqual(self.entries(), [])


class LocalArtwork(ArtworkCase):
    def local_file(self, name, size):
        path = os.path.join(self.tmp.name, name)
        with open(path, "wb") as handle:
            handle.truncate(size)
        return path

    def test_a_cover_on_disk_is_passed_through_unchanged(self):
        path = self.local_file("cover art.png", 100)
        url = "file://" + urllib.parse.quote(path)
        self.assertEqual(helper.resolve(url, allow_http=False), url)
        self.assertEqual(self.entries(), [], "local covers are not copied")

    def test_a_cover_on_disk_over_the_limit_is_refused(self):
        path = self.local_file("huge.png", LIMIT + 1)
        with self.assertRaises(helper.TooLarge):
            helper.resolve("file://" + path, allow_http=False)

    def test_things_on_disk_that_are_not_regular_files_are_refused(self):
        fifo = os.path.join(self.tmp.name, "fifo")
        os.mkfifo(fifo)
        for path in (fifo, "/dev/zero", self.tmp.name, os.path.join(self.tmp.name, "absent")):
            with self.assertRaises(helper.Blocked, msg=path):
                helper.resolve("file://" + path, allow_http=False)

    def test_file_urls_naming_another_host_are_refused(self):
        with self.assertRaises(helper.Blocked):
            helper.resolve("file://server/share/cover.png", allow_http=False)


if __name__ == "__main__":
    unittest.main()
