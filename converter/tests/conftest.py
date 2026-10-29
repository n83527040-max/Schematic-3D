from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "converter" / "src"))

import pytest  # noqa: E402


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return ROOT


@pytest.fixture(scope="session")
def fixtures_dir() -> Path:
    return Path(__file__).resolve().parent / "fixtures"


@pytest.fixture(scope="session")
def examples_dir() -> Path:
    p = ROOT / "examples"
    if not p.exists():  # regenerate on demand so a fresh clone can run tests
        import subprocess
        subprocess.run([sys.executable, str(ROOT / "scripts" / "gen_examples.py")],
                       check=True)
    return p
