from __future__ import annotations

import platform
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import TextIO

from .errors import ProcessFailed

PHASE_CLOSE_MARKER = "PHASE_FINISHED_CAN_CLOSE"
TERMINATE_TIMEOUT_SECONDS = 5.0


class ProcessRunner:
    def run(
        self,
        argv: list[str],
        *,
        check: bool = True,
        cwd: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        completed = subprocess.run(
            argv,
            cwd=cwd,
            text=True,
            capture_output=True,
            check=False,
        )
        if check and completed.returncode != 0:
            raise ProcessFailed(argv, completed.returncode, stderr_tail=completed.stderr[-2048:])
        return completed

    def run_with_log(
        self,
        argv: list[str],
        log_path: Path,
        *,
        needs_tty: bool = False,
        capture_log: bool = True,
        check: bool = True,
        cwd: Path | None = None,
        output: TextIO | None = None,
        close_marker: str | None = None,
        terminate_on_close_marker: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        out = output if output is not None else sys.stdout
        run_argv = _script_argv(argv, log_path) if needs_tty and sys.stdout.isatty() else argv

        if not capture_log:
            completed = subprocess.run(run_argv, cwd=cwd, text=True, check=False)
            if check and completed.returncode != 0:
                raise ProcessFailed(argv, completed.returncode, log_path=log_path)
            return completed

        with log_path.open("w", encoding="utf-8", errors="replace") as log_file:
            proc = subprocess.Popen(
                run_argv,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
            )
            assert proc.stdout is not None
            chunks: list[str] = []
            marker_seen = False
            marker_scan_buffer = ""
            for chunk in proc.stdout:
                chunks.append(chunk)
                log_file.write(chunk)
                log_file.flush()
                out.write(chunk)
                out.flush()

                if close_marker is not None:
                    marker_scan_buffer = marker_scan_buffer + chunk
                    marker_seen = close_marker in marker_scan_buffer
                    marker_scan_buffer = marker_scan_buffer[-len(close_marker) :]
                    if marker_seen and terminate_on_close_marker:
                        proc.terminate()
                        break
            returncode = _wait_after_marker_termination(proc) if marker_seen else proc.wait()

        stdout = "".join(chunks)
        effective_returncode = 0 if marker_seen and terminate_on_close_marker else returncode
        completed = subprocess.CompletedProcess(run_argv, effective_returncode, stdout=stdout, stderr="")
        if check and effective_returncode != 0:
            raise ProcessFailed(
                argv,
                effective_returncode,
                log_path=log_path,
                stderr_tail=stdout[-2048:],
            )
        return completed


def _script_argv(argv: list[str], log_path: Path) -> list[str]:
    if platform.system() == "Darwin":
        return ["script", "-q", str(log_path), *argv]
    return ["script", "-q", "-e", "-c", shlex.join(argv), str(log_path)]


def _wait_after_marker_termination(proc: subprocess.Popen[str]) -> int:
    deadline = time.monotonic() + TERMINATE_TIMEOUT_SECONDS
    while True:
        try:
            return proc.wait(timeout=0.1)
        except subprocess.TimeoutExpired:
            if time.monotonic() >= deadline:
                proc.kill()
                return proc.wait()
