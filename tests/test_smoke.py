"""Test the endpoint checker without contacting local or remote services."""

import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import URLError


SPEC = importlib.util.spec_from_file_location(
    "searxng_smoke", Path(__file__).with_name("searxng-smoke.py")
)
SMOKE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SMOKE)


class Response(io.BytesIO):
    def __init__(self, body, content_type, status=200):
        super().__init__(body)
        self.status = status
        self.headers = {"Content-Type": content_type}


class SmokeTests(unittest.TestCase):
    def test_home_accepts_html(self):
        SMOKE.check_home(Response(b"<html>Search</html>", "text/html; charset=utf-8"))

    def test_home_rejects_empty_or_error_pages(self):
        for body, status in ((b"", 200), (b"Error", 500)):
            with self.subTest(status=status), self.assertRaises(AssertionError):
                SMOKE.check_home(Response(body, "text/html", status))

    def test_json_allows_empty_results(self):
        SMOKE.check_json(Response(b'{"results": []}', "application/json"))

    def test_json_rejects_invalid_responses(self):
        for body in (b"not json", b"[]", b"{}", b'{"results": null}'):
            with self.subTest(body=body), self.assertRaises((ValueError, AssertionError)):
                SMOKE.check_json(Response(body, "application/json"))

    def test_json_rejects_html(self):
        with self.assertRaises(AssertionError):
            SMOKE.check_json(Response(b"<html>Error</html>", "text/html"))

    def test_wait_retries_connection_failures(self):
        response = Response(b"<html>Ready</html>", "text/html")
        with patch.object(SMOKE, "urlopen", side_effect=[URLError("not ready"), response]) as request:
            with patch.object(SMOKE.time, "sleep"), patch("builtins.print"):
                SMOKE.wait_for("http://example.invalid", SMOKE.check_home)
        self.assertEqual(request.call_count, 2)

    def test_wait_fails_on_timeout(self):
        with patch.object(SMOKE.time, "monotonic", side_effect=[0, 0, 121]):
            with patch.object(SMOKE.time, "sleep"):
                with patch.object(SMOKE, "urlopen", side_effect=URLError("not ready")):
                    with self.assertRaisesRegex(SystemExit, "Timed out checking"):
                        SMOKE.wait_for("http://example.invalid", SMOKE.check_home)


if __name__ == "__main__":
    unittest.main()