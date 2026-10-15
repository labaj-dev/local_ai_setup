"""Exercise the real Bash entry points without installing or starting anything."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")

# Every external command with side effects is intercepted. All files and mock
# state are private to each test, including when a script changes directory.
MOCK = r'''
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps([name] + args) + "\n")
if name == "podman":
    if args[:2] == ["machine", "list"]:
        if args[-1] == "{{.Name}}":
            print(os.environ.get("MOCK_MACHINE_NAME", "podman-machine-default"))
        else:
            print(os.environ.get("MOCK_RUNNING", "true"))
    elif args[:1] == ["exec"]:
        sys.stdin.read()
        print(os.environ.get("MOCK_WEBUI", "unchanged"))
elif name == "podman-compose":
    sys.exit(int(os.environ.get("MOCK_COMPOSE_EXIT", "0")))
elif name == "curl":
    sys.exit(int(os.environ.get("MOCK_CURL_EXIT", "0")))
elif name == "ollama" and args == ["--version"]:
    print("ollama version is test")
elif name == "sysctl":
    print({"hw.memsize": "17179869184", "hw.ncpu": "8",
           "machdep.cpu.brand_string": "Test CPU"}[args[-1]])
elif name == "uname":
    print("arm64")
elif name == "nproc":
    print("8")
elif name == "security":
    state = Path(os.environ["MOCK_KEY"])
    if args[0] == "find-generic-password":
        if not state.exists():
            sys.exit(44)
        if "-w" in args:
            print(state.read_text())
    elif args[0] == "add-generic-password":
        state.write_text(args[args.index("-p") + 1])
    elif args[0] == "delete-generic-password":
        state.unlink()
    else:
        sys.exit("Unexpected security command")
'''


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="local-ai-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo with spaces"
        self.repo.mkdir()
        for script in ROOT.glob("*.sh"):
            shutil.copy2(script, self.repo)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for command in ("podman", "podman-compose", "brew", "ollama", "curl",
                        "code", "sudo", "apt-get", "dnf", "systemctl", "nohup",
                        "sleep", "security", "sysctl", "uname", "nproc", "nvidia-smi"):
            path = self.bin / command
            path.write_text("#!" + sys.executable + "\n" + MOCK)
            path.chmod(0o755)
        # Key generation is real Python, but all Keychain access is mocked.
        (self.bin / "python3").symlink_to(sys.executable)
        self.log = self.base / "commands.jsonl"
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith("MOCK_") or key in (
                "BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "OLLAMA_MODEL",
                "SKIP_MODEL", "SKIP_CLINE",
            ):
                self.env.pop(key, None)
        self.env.update(
            PATH=str(self.bin) + os.pathsep + os.defpath,
            HOME=str(self.base), USER="ci-test", SKIP_MODEL="1", SKIP_CLINE="1",
            MOCK_LOG=str(self.log), MOCK_KEY=str(self.base / "secret"),
        )

    def run_script(self, script, *args, os_type="darwin", expected=0, **env):
        result = subprocess.run(
            [BASH, str(self.repo / script), *args],
            cwd=self.base, env=dict(self.env, OSTYPE=os_type, **env),
            input="", text=True, capture_output=True, timeout=15,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_setup_skip_flags_do_not_pull_models_or_install_cline(self):
        for os_type in ("darwin", "linux-gnu"):
            with self.subTest(os_type=os_type):
                self.run_script("setup.sh", os_type=os_type)
        calls = self.calls()
        self.assertNotIn(["code", "--install-extension", "saoudrizwan.claude-dev"], calls)
        self.assertFalse(any(call[:2] == ["ollama", "pull"] for call in calls))
        self.assertIn(["brew", "install", "podman", "podman-compose"], calls)

    def test_setup_creates_and_starts_missing_mac_machine(self):
        self.run_script("setup.sh", MOCK_MACHINE_NAME="", MOCK_RUNNING="false")
        self.assertIn(["podman", "machine", "init", "--cpus", "4", "--memory",
                       "4096", "--disk-size", "60"], self.calls())
        self.assertIn(["podman", "machine", "start"], self.calls())

    def test_setup_rejects_unsupported_os(self):
        output = self.run_script("setup.sh", os_type="unsupported", expected=1)
        self.assertIn("Unsupported OS", output)
        self.assertFalse(self.log.exists())

    def test_start_uses_platform_compose_files(self):
        for os_type in ("darwin", "linux-gnu"):
            with self.subTest(os_type=os_type):
                if self.log.exists():
                    self.log.unlink()
                self.run_script("start.sh", os_type=os_type)
                expected = ["podman-compose", "-f", "docker-compose.yml"]
                if os_type != "darwin":
                    expected += ["-f", "docker-compose.linux.yml"]
                self.assertIn(expected + ["up", "-d"], self.calls())
                self.assertNotIn(["podman", "restart", "open-webui"], self.calls())
                if os_type != "darwin":
                    self.assertFalse(any(call[:2] == ["podman", "machine"]
                                         for call in self.calls()))

    def test_start_starts_stopped_mac_machine(self):
        self.run_script("start.sh", MOCK_RUNNING="false")
        self.assertIn(["podman", "machine", "start"], self.calls())

    def test_start_restarts_webui_only_when_defaults_changed(self):
        self.run_script("start.sh", MOCK_WEBUI="changed")
        self.assertIn(["podman", "restart", "open-webui"], self.calls())

    def test_start_propagates_compose_failure(self):
        self.run_script("start.sh", MOCK_COMPOSE_EXIT="17", expected=17)
        self.assertFalse(any(call[:2] == ["podman", "exec"] for call in self.calls()))

    def test_start_fails_when_searxng_is_unreachable(self):
        output = self.run_script("start.sh", MOCK_CURL_EXIT="7", expected=1)
        self.assertIn("SearXNG did not respond", output)

    def test_stop_uses_platform_compose_files(self):
        for os_type in ("darwin", "linux-gnu"):
            with self.subTest(os_type=os_type):
                self.run_script("stop.sh", os_type=os_type)
                expected = ["podman-compose", "-f", "docker-compose.yml"]
                if os_type != "darwin":
                    expected += ["-f", "docker-compose.linux.yml"]
                self.assertIn(expected + ["down"], self.calls())

    def test_keychain_lifecycle_with_mocked_security(self):
        self.run_script("searxng-keychain-setup.sh")
        key_file = Path(self.env["MOCK_KEY"])
        original = key_file.read_text()
        self.assertEqual(len(original), 43)
        self.assertIn(original, self.run_script("searxng-keychain-usage.sh", "show"))
        self.run_script("searxng-keychain-setup.sh")
        self.assertNotEqual(key_file.read_text(), original)
        previous = key_file.read_text()
        self.run_script("searxng-keychain-usage.sh", "reset")
        self.assertNotEqual(key_file.read_text(), previous)
        self.run_script("searxng-keychain-usage.sh", "remove")
        self.assertFalse(key_file.exists())
        self.assertIn("No key found", self.run_script("searxng-keychain-usage.sh", "show"))
        self.run_script("searxng-keychain-usage.sh", "remove")

    def test_keychain_setup_rejects_linux(self):
        self.run_script("searxng-keychain-setup.sh", os_type="linux-gnu", expected=1)
        self.assertFalse(self.log.exists())

    def test_keychain_help(self):
        self.assertIn("Usage:", self.run_script("searxng-keychain-usage.sh"))


if __name__ == "__main__":
    unittest.main()