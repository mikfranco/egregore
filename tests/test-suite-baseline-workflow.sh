#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import re, subprocess, sys, tempfile, os, json
root = Path(sys.argv[1])
workflow = (root / ".github/workflows/ci.yml").read_text()
job = workflow.split("  baseline:\n", 1)[1].split("  shellcheck:", 1)[0]
assert "fetch-depth: 0" in job
assert "--exclude-owned --selected" in job
assert "timeout --kill-after=10s 300s" in job
assert "if-no-files-found: ignore" in job
assert "test-baseline.sh" not in job
script = job.split("      - name: Run distributed shell suites", 1)[1].split("        run: |\n", 1)[1].split("      - name: Upload", 1)[0]
script = "\n".join(line[10:] for line in script.splitlines())
script = script.replace("${{ matrix.shard }}", "0")
with tempfile.TemporaryDirectory() as temporary:
    tree = Path(temporary)
    (tree / "bin").mkdir()
    (tree / "tests").mkdir()
    (tree / "bin/suite-shard.sh").write_text("printf '%s\\n' tests/pass.sh tests/fail.sh tests/last.sh\n")
    for name, code in (("pass", 0), ("fail", 37), ("last", 0)):
        (tree / f"tests/{name}.sh").write_text(f"echo {name}\nexit {code}\n")
    env = {**os.environ, "RUNNER_TEMP": temporary, "GITHUB_STEP_SUMMARY": str(tree / "summary"),
           "BASELINE_SUITES": "[]", "BASELINE_SHARD_COUNT": "1"}
    result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script], cwd=tree, env=env, capture_output=True, text=True)
    assert result.returncode == 1, result.stderr
    assert "PASS tests/last.sh" in result.stdout, result.stdout
    assert "FAIL tests/fail.sh (exit 37)" in result.stdout
    assert (tree / "suite-logs/tests_fail.sh.log").read_text() == "fail\n"
    (tree / "tests/fail.sh").write_text("exit 0\n")
    result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script], cwd=tree, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
print("Public shell shard success, failure propagation, continued coverage and logs verified")
PYTEST
