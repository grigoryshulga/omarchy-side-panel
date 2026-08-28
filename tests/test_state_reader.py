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
        return subprocess.run(
            ["/usr/bin/python3", "-I", str(READER), str(path), str(maximum)],
            capture_output=True,
            check=False,
            timeout=2,
        )

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

    def test_distinguishes_a_missing_file_from_other_io_errors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            self.assertEqual(self.run_reader(path / "missing.json").returncode, 1)
            too_long = path / ("x" * 5000)
            self.assertEqual(self.run_reader(too_long).returncode, 4)

    def test_rejects_relative_paths_and_files_writable_by_other_users(self) -> None:
        self.assertEqual(self.run_reader(Path("relative-state.json")).returncode, 3)
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            state_path.write_bytes(b'{}')
            state_path.chmod(0o666)
            self.assertEqual(self.run_reader(state_path).returncode, 3)

    def test_rejects_a_state_directory_writable_by_other_users(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory) / "insecure"
            parent.mkdir()
            parent.chmod(0o777)
            state_path = parent / "state.json"
            state_path.write_bytes(b'{}')

            self.assertEqual(self.run_reader(state_path).returncode, 3)

    def test_rejects_a_size_limit_above_the_absolute_maximum(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            state_path.write_bytes(b'{}')

            self.assertEqual(self.run_reader(state_path, 10**12).returncode, 3)
