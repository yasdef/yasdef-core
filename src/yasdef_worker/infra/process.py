from __future__ import annotations

import os
import platform
import shlex
import signal
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
        uses_tty_wrapper = needs_tty and sys.stdout.isatty()
        run_argv = _script_argv(argv, log_path) if uses_tty_wrapper else argv

        if not capture_log:
            completed = subprocess.run(run_argv, cwd=cwd, text=True, check=False)
            if check and completed.returncode != 0:
                raise ProcessFailed(argv, completed.returncode, log_path=log_path)
            return completed

        if uses_tty_wrapper:
            # Direct passthrough: script writes output to the real terminal and logs to
            # log_path itself. No stdout pipe — the TUI renders natively.
            # Close-marker detection via log tailing is tracked in crp-140.
            proc = subprocess.Popen(run_argv, cwd=cwd, start_new_session=True)
            old_sigint = signal.signal(signal.SIGINT, _make_sigint_relay(proc))
            try:
                returncode = proc.wait()
            finally:
                signal.signal(signal.SIGINT, old_sigint)
                _restore_terminal()

            log_text = _read_log(log_path)
            completed = subprocess.CompletedProcess(run_argv, returncode, stdout=log_text, stderr="")
            if check and returncode != 0:
                raise ProcessFailed(argv, returncode, log_path=log_path, stderr_tail=log_text[-2048:])
            return completed

        with log_path.open("w", encoding="utf-8", errors="replace") as log_file:
            proc = subprocess.Popen(
                run_argv,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                start_new_session=terminate_on_close_marker,
            )
            old_sigint = signal.signal(signal.SIGINT, _make_sigint_relay(proc))
            try:
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
                            _terminate_process(proc)
                            break
                returncode = _wait_after_marker_termination(proc) if marker_seen else proc.wait()
            finally:
                signal.signal(signal.SIGINT, old_sigint)

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


def _read_log(log_path: Path) -> str:
    try:
        return log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
    except OSError:
        return ""


def _wait_after_marker_termination(proc: subprocess.Popen[str]) -> int:
    deadline = time.monotonic() + TERMINATE_TIMEOUT_SECONDS
    while True:
        try:
            return proc.wait(timeout=0.1)
        except subprocess.TimeoutExpired:
            if time.monotonic() >= deadline:
                _kill_process(proc)
                return proc.wait()


def _make_sigint_relay(proc: subprocess.Popen[str]):
    def _handler(_signum: int, _frame: object) -> None:
        try:
            if proc.poll() is None:
                if hasattr(os, "killpg"):
                    os.killpg(proc.pid, signal.SIGINT)
                else:
                    proc.send_signal(signal.SIGINT)
        except ProcessLookupError:
            pass
        raise KeyboardInterrupt

    return _handler


def _terminate_process(proc: subprocess.Popen[str]) -> None:
    try:
        if proc.poll() is None:
            if hasattr(os, "killpg"):
                os.killpg(proc.pid, signal.SIGTERM)
            else:
                proc.terminate()
    except ProcessLookupError:
        return


def _kill_process(proc: subprocess.Popen[str]) -> None:
    try:
        if proc.poll() is None:
            if hasattr(os, "killpg"):
                os.killpg(proc.pid, signal.SIGKILL)
            else:
                proc.kill()
    except ProcessLookupError:
        return


def _restore_terminal() -> None:
    try:
        subprocess.run(["stty", "sane"], stdin=sys.stdin, check=False)
    except OSError:
        return
