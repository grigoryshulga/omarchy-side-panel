"""Tests for the bounded, descriptor-based state reader."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parents[1]
READER = PROJECT_DIR / "bin" / "omarchy-side-panel-read-state"


class StateReaderTests(unittest.TestCase):
    def run_reader(self, path: Path, maximum: int = 64) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(["python3", str(READER), str(path), str(maximum)], capture_output=True, check=False)

    def test_reads_a_regular_file_within_the_limit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            state_path.write_bytes(b'{"version":1}')
            result = self.run_reader(state_path)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b'{"version":1}')

    def test_rejects_a_symlink_without_reading_its_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            target = path / "target.json"
            target.write_bytes(b"target")
            state_path = path / "state.json"
            state_path.symlink_to(target)
            result = self.run_reader(state_path)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(result.stdout, b"")

    def test_rejects_a_fifo_without_blocking(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            os.mkfifo(state_path)
            result = self.run_reader(state_path)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(result.stdout, b"")

    def test_rejects_files_larger_than_the_limit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            state_path.write_bytes(b"x" * 65)
            result = self.run_reader(state_path)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, b"")
