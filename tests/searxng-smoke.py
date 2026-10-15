"""Check a running CI SearXNG container using only the Python standard library."""

import json
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


def wait_for(url, validate, timeout=120):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            with urlopen(url, timeout=10) as response:
                validate(response)
            print("Passed:", url)
            return
        except (HTTPError, URLError, OSError, ValueError, AssertionError) as error:
            last_error = error
            time.sleep(2)
    raise SystemExit(f"Timed out checking {url}: {last_error}")


def check_home(response):
    assert response.status == 200, response.status
    assert "text/html" in response.headers.get("Content-Type", "")
    assert response.read(), "Empty home page"


def check_json(response):
    assert response.status == 200, response.status
    assert "application/json" in response.headers.get("Content-Type", "")
    data = json.load(response)
    assert isinstance(data, dict), "Expected a JSON object"
    assert isinstance(data.get("results"), list), "Missing search results array"
    # Search providers may block CI IPs. Results need not be nonempty: this
    # tests local JSON search support, not third-party search-engine uptime.


if __name__ == "__main__":
    wait_for("http://127.0.0.1:8080/", check_home)
    wait_for("http://127.0.0.1:8080/search?q=hello&format=json", check_json)