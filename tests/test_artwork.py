"""Tests for bin/artwork, the helper that bounds what album art can cost.

Run with: python3 -m unittest discover -s tests

Qt's Image buffers an http(s) response whole before decoding it, so the
helper is what keeps a cover server from exhausting the shell's memory. These
serve covers from a throwaway server on loopback and check that oversized,
endless, slow, and redirected answers never reach the cache. Size alone does
not bound what Qt spends decoding a cover, so these also check that every
cover, downloaded or on disk, reaches the shell only as a PNG or JPEG of
bounded dimensions with nothing in it but what draws the picture.
"""

import base64
import hashlib
import http.client
import http.server
import importlib.machinery
import importlib.util
import io
import json
import os
import stat
import struct
import tempfile
import threading
import time
import unittest
import urllib.parse
import zlib
from contextlib import redirect_stdout
from unittest import mock

HELPER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "artwork")
spec = importlib.util.spec_from_loader("artwork", importlib.machinery.SourceFileLoader("artwork", HELPER))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
# The real check, before the tests let their loopback server past it.
PUBLIC_ADDRESS = helper.public_address

LIMIT = 4096


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def png(width=2, height=2, extra=(), pixels=None, after=b""):
    """An 8-bit RGB PNG, with `extra` chunks between its header and pixels."""
    if pixels is None:
        pixels = (b"\x00" + b"\x7f" * (3 * width)) * height
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + b"".join(extra) + chunk(b"IDAT", zlib.compress(pixels))
            + chunk(b"IEND", b"") + after)


# A megabyte of text that compresses to about a kilobyte: what a decoder that
# reads metadata would inflate, many times over in a real attack.
BOMB = zlib.compress(b"\x00" * (1 << 20), 9)
TRANSPARENCY = chunk(b"tRNS", b"\x00\x00\x00\x00\x00\x00")
METADATA = (chunk(b"tEXt", b"Comment\x00hello"),
            chunk(b"zTXt", b"Comment\x00\x00" + BOMB),
            chunk(b"iTXt", b"XML:com.adobe.xmp\x00\x01\x00\x00\x00" + BOMB),
            chunk(b"iCCP", b"icc\x00\x00" + BOMB))
COVER = png()
# The same picture, carrying compressed metadata a decoder would inflate.
LOADED_COVER = png(extra=METADATA)
# A few dozen bytes that declare ten billion pixels.
HUGE_COVER = png(width=100000, height=100000, pixels=b"")

# Written by ImageMagick with -strip: a 4x4 baseline JPEG and a progressive
# one, and a 5x3 16-bit interlaced PNG.
JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYU"
    "GBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAAEAAQD"
    "AREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAAB//EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAVAQEBAAAAAAAAAAAAAAAAAAAHCP/EABQRAQAA"
    "AAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/ACwdLLf/2Q==")
PROGRESSIVE_JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYU"
    "GBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wgARCAAEAAQD"
    "AREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAABf/EABQBAQAAAAAAAAAAAAAAAAAAAAf/2gAMAwEAAhADEAAAAUTsp//EABQQAQAAAAAAAAAA"
    "AAAAAAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Bf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8B"
    "f//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEABj8Cf//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAT8hf//aAAwDAQACAAMAAAAQv//E"
    "ABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Qf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Qf//EABQQAQAAAAAAAAAAAAAAAAAA"
    "AAD/2gAIAQEAAT8Qf//Z")
INTERLACED_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAUAAAADEAIAAAHzw756AAAAJElEQVQI12P4/5+BgYGBAYViRBKBAkZkLoo8YwMDA0MDAy4AAHYCDPms+7ciAAAA"
    "AElFTkSuQmCC")


def segment(marker, body):
    return bytes((0xFF, marker)) + struct.pack(">H", len(body) + 2) + body


def after_app0(jpeg, *segments):
    """`jpeg` with `segments` inserted after its JFIF header."""
    split = 4 + struct.unpack(">H", jpeg[4:6])[0]
    return jpeg[:split] + b"".join(segments) + jpeg[split:]


class Handler(http.server.BaseHTTPRequestHandler):
    hits = []

    def log_message(self, *args):
        pass

    def do_GET(self):
        Handler.hits.append(self.path)
        route = self.path.split("?")[0]
        if route == "/cover.png":
            self.answer(COVER)
        elif route == "/loaded.png":
            self.answer(LOADED_COVER)
        elif route == "/huge.png":
            self.answer(HUGE_COVER)
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
        elif route == "/to-private":
            self.redirect("http://10.0.0.1/cover.png")
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
        # The covers come from a throwaway server on loopback, which the
        # helper refuses like any other local address; only it is let through.
        public = helper.public_address
        patches = [mock.patch.object(helper, "CACHE_DIR", self.cache),
                   mock.patch.object(helper, "MAX_ARTWORK_BYTES", LIMIT),
                   mock.patch.object(helper, "public_address",
                                     lambda text: text == "127.0.0.1" or public(text))]
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


class CleanArtwork(unittest.TestCase):
    """What Qt decodes in the shell's own process: never more than a bounded
    picture, and nothing it would have to inflate to find that out."""

    def test_a_png_keeps_only_the_chunks_that_draw_it(self):
        loaded = png(extra=METADATA + (TRANSPARENCY,), after=b"trailing junk")
        self.assertEqual(helper.clean(loaded), png(extra=(TRANSPARENCY,)))
        self.assertEqual(helper.clean(COVER), COVER)

    def test_interlaced_and_16_bit_pngs_are_kept(self):
        self.assertEqual(helper.clean(INTERLACED_PNG), INTERLACED_PNG)

    def test_a_png_declaring_a_huge_picture_is_refused(self):
        side = helper.MAX_IMAGE_SIDE
        for width, height in ((100000, 100000), (side + 1, 1), (1, side + 1), (0, 1)):
            row = b"\x00" + b"\x7f" * 3 * width
            pixels = row * height if width * height < 1 << 16 else b""
            with self.assertRaises(helper.BadImage, msg=(width, height)):
                helper.clean(png(width=width, height=height, pixels=pixels))

    def test_a_png_whose_pixels_inflate_past_its_size_is_refused(self):
        # Two by two pixels need 14 bytes; this inflates to a megabyte.
        with self.assertRaises(helper.BadImage):
            helper.clean(png(pixels=b"\x00" * (1 << 20)))

    def test_a_damaged_or_incomplete_png_is_refused(self):
        damaged = bytearray(COVER)
        damaged[-20] ^= 0xFF
        cases = {
            "damaged": bytes(damaged),
            "cut short": COVER[:-12],
            "missing pixels": png(pixels=b"\x00" * 7),
            "unknown critical chunk": png(extra=(chunk(b"ABCD", b""),)),
            "second header": png(extra=(COVER[8:33],)),
            "no header": COVER[:8] + COVER[33:],
        }
        for name, data in cases.items():
            with self.assertRaises(helper.BadImage, msg=name):
                helper.clean(data)

    def test_a_jpeg_keeps_only_the_segments_that_draw_it(self):
        loaded = after_app0(JPEG, segment(0xE1, b"Exif\x00\x00" + b"x" * 100),
                            segment(0xE2, b"ICC_PROFILE\x00\x01\x01" + b"x" * 100),
                            segment(0xFE, b"a comment"))
        self.assertEqual(helper.clean(loaded + b"trailing junk"), JPEG)
        self.assertEqual(helper.clean(PROGRESSIVE_JPEG), PROGRESSIVE_JPEG)

    def test_a_jpeg_declaring_a_huge_picture_is_refused(self):
        frame = JPEG.index(b"\xff\xc0")
        for height, width in ((0xFFFF, 0xFFFF), (helper.MAX_IMAGE_SIDE + 1, 4), (0, 4)):
            data = JPEG[:frame + 5] + struct.pack(">HH", height, width) + JPEG[frame + 9:]
            with self.assertRaises(helper.BadImage, msg=(height, width)):
                helper.clean(data)

    def test_a_jpeg_that_takes_too_many_scans_is_refused(self):
        start = JPEG.index(b"\xff\xda")
        scan = JPEG[start:-2]
        many = JPEG[:start] + scan * (helper.MAX_JPEG_SCANS + 1) + b"\xff\xd9"
        with self.assertRaises(helper.BadImage):
            helper.clean(many)
        allowed = JPEG[:start] + scan * helper.MAX_JPEG_SCANS + b"\xff\xd9"
        self.assertEqual(helper.clean(allowed), allowed)

    def test_a_jpeg_of_a_kind_or_shape_it_does_not_know_is_refused(self):
        frame = JPEG.index(b"\xff\xc0")
        cases = {
            "arithmetic coded": JPEG[:frame + 1] + b"\xc9" + JPEG[frame + 2:],
            "cut short": JPEG[:-40],
            "no scan": JPEG[:JPEG.index(b"\xff\xda")] + b"\xff\xd9",
        }
        for name, data in cases.items():
            with self.assertRaises(helper.BadImage, msg=name):
                helper.clean(data)

    def test_anything_but_png_and_jpeg_is_refused(self):
        for data in (b"", b"GIF89a\x01\x00\x01\x00", b"RIFF\x00\x00\x00\x00WEBPVP8 ",
                     b"<svg xmlns='http://www.w3.org/2000/svg'/>", b"BM" + b"\x00" * 60,
                     b"\x00" * 200):
            with self.assertRaises(helper.BadImage, msg=data[:8]):
                helper.clean(data)


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

    def test_a_cover_reaches_the_cache_without_its_metadata(self):
        source = helper.resolve(self.url("/loaded.png"), allow_http=True)
        with open(urllib.parse.unquote(urllib.parse.urlsplit(source).path), "rb") as handle:
            self.assertEqual(handle.read(), COVER)

    def test_a_cover_declaring_a_huge_picture_is_refused_and_not_kept(self):
        with self.assertRaises(helper.BadImage):
            helper.resolve(self.url("/huge.png"), allow_http=True)
        self.assertEqual(self.entries(), [])

    def test_a_cover_an_older_version_cached_is_not_handed_out(self):
        # Before covers were cleaned, an entry was named after the URL alone
        # and held whatever the server sent.
        url = self.url("/cover.png")
        os.makedirs(self.cache, mode=0o700)
        old = os.path.join(self.cache, hashlib.sha256(url.encode()).hexdigest())
        with open(old, "wb") as handle:
            handle.write(HUGE_COVER)
        source = helper.resolve(url, allow_http=True)
        self.assertNotEqual(urllib.parse.unquote(urllib.parse.urlsplit(source).path), old)
        self.assertEqual(Handler.hits, ["/cover.png"])

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


class PrivateNetworks(ArtworkCase):
    """The player picks the cover's address, so a cover is fetched only from
    the public internet, never from this machine or its networks."""

    PUBLIC = ("1.1.1.1", "8.8.8.8", "2606:4700::1111", "::ffff:1.1.1.1", "64:ff9b::808:808")
    LOCAL = ("127.0.0.1", "127.8.8.8", "0.0.0.0", "10.1.2.3", "172.16.0.1", "192.168.1.1",
             "169.254.169.254", "100.64.0.1", "224.0.0.1", "255.255.255.255",
             "::", "::1", "fe80::1", "fe80::1%eth0", "fc00::1", "ff02::1",
             "::ffff:127.0.0.1", "::ffff:192.168.0.1", "2002:c0a8:0101::1",
             "64:ff9b::a00:1", "not an address")

    def test_only_public_addresses_pass(self):
        public = PUBLIC_ADDRESS
        for address in self.PUBLIC:
            self.assertTrue(public(address), address)
        for address in self.LOCAL:
            self.assertFalse(public(address), address)

    def test_a_cover_on_this_machine_is_refused_without_connecting(self):
        with mock.patch.object(helper, "public_address", PUBLIC_ADDRESS):
            with self.assertRaises(helper.Blocked):
                helper.resolve(self.url("/cover.png"), allow_http=True)
            with self.assertRaises(helper.Blocked):
                helper.resolve("https://localhost/cover.png", allow_http=False)
        self.assertEqual(Handler.hits, [])
        self.assertEqual(self.entries(), [])

    def test_a_redirect_to_a_private_network_is_refused(self):
        with self.assertRaises(helper.Blocked):
            helper.resolve(self.url("/to-private"), allow_http=True)
        self.assertEqual(Handler.hits, ["/to-private"])
        self.assertEqual(self.entries(), [])

    def test_a_name_with_any_private_address_is_refused_before_connecting(self):
        # A name can resolve to a public address and a private one at once.
        answers = [(helper.socket.AF_INET, helper.socket.SOCK_STREAM, 6, "", (address, 443))
                   for address in ("93.184.216.34", "192.168.0.1")]
        with mock.patch.object(helper.socket, "getaddrinfo", return_value=answers), \
                mock.patch.object(helper.socket, "socket") as opened:
            with self.assertRaises(helper.Blocked):
                helper.public_connection(("covers.example", 443), 5)
        opened.assert_not_called()

    def test_the_address_checked_is_the_one_connected_to(self):
        answers = [(helper.socket.AF_INET, helper.socket.SOCK_STREAM, 6, "", ("93.184.216.34", 443))]
        with mock.patch.object(helper.socket, "getaddrinfo", return_value=answers), \
                mock.patch.object(helper.socket, "socket") as opened:
            helper.public_connection(("covers.example", 443), 5)
        opened.return_value.connect.assert_called_once_with(("93.184.216.34", 443))

    def test_proxy_settings_are_not_used(self):
        # A proxy would make the connection instead, past the address check.
        proxies = {"http_proxy": "http://192.168.0.1:3128", "https_proxy": "http://192.168.0.1:3128",
                   "HTTP_PROXY": "http://192.168.0.1:3128", "HTTPS_PROXY": "http://192.168.0.1:3128"}
        with mock.patch.dict(os.environ, proxies):
            source = helper.resolve(self.url("/cover.png"), allow_http=True)
        self.assertTrue(source.startswith("file://"))
        self.assertEqual(Handler.hits, ["/cover.png"])



class Main(ArtworkCase):
    def test_the_url_comes_from_the_environment_and_does_not_linger(self):
        code, payload, leaked = self.run_main(self.url("/cover.png"), request="7")
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["request"], "7")
        self.assertTrue(payload["source"].startswith("file://" + urllib.parse.quote(self.cache)))
        self.assertEqual(leaked, [])

    def test_failures_are_reported_as_json(self):
        cases = {"/endless": "too_large", "/missing": "http", "/to-ftp": "blocked",
                 "/huge.png": "image", "/to-private": "blocked"}
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
    def local_file(self, name, size=0, data=b""):
        path = os.path.join(self.tmp.name, name)
        with open(path, "wb") as handle:
            handle.write(data)
            if size:
                handle.truncate(size)
        return path

    def test_a_cover_on_disk_is_cleaned_into_the_cache(self):
        # Players often hand over a file a browser saved from a web page.
        path = self.local_file("cover art.png", data=LOADED_COVER)
        source = helper.resolve("file://" + urllib.parse.quote(path), allow_http=False)
        cached = urllib.parse.unquote(urllib.parse.urlsplit(source).path)
        self.assertEqual(os.path.dirname(cached), self.cache)
        with open(cached, "rb") as handle:
            self.assertEqual(handle.read(), COVER)
        with open(path, "rb") as handle:
            self.assertEqual(handle.read(), LOADED_COVER, "the player's file is left alone")

    def test_a_cover_on_disk_that_changes_is_cleaned_again(self):
        path = self.local_file("cover.jpg", data=JPEG)
        first = helper.resolve("file://" + path, allow_http=False)
        self.local_file("cover.jpg", data=PROGRESSIVE_JPEG)
        second = helper.resolve("file://" + path, allow_http=False)
        self.assertNotEqual(first, second)

    def test_a_cover_on_disk_declaring_a_huge_picture_is_refused(self):
        path = self.local_file("huge.png", data=HUGE_COVER)
        with self.assertRaises(helper.BadImage):
            helper.resolve("file://" + path, allow_http=False)
        self.assertEqual(self.entries(), [])

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
