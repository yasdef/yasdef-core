"""Integration tests for `yasdef init` — ports init_asdlc_worker_tests.sh."""
from __future__ import annotations

from pathlib import Path

from .conftest import git, seed_repo, yasdef

SKILL_NAMES = [
    "yasdef-worker-design",
    "yasdef-worker-plan",
    "yasdef-worker-implementation",
    "yasdef-worker-user-review",
    "yasdef-worker-ai-audit",
]
PREFIXES = [".claude", ".codex", ".github", ".agents"]


def _assert_skill_files(repo: Path, prefix: str, skill: str) -> None:
    base = repo / prefix / "skills" / skill
    assert (base / "SKILL.md").is_file(), f"missing {prefix}/skills/{skill}/SKILL.md"


def test_init_fails_when_target_missing(tmp_path: Path) -> None:
    result = yasdef("init", str(tmp_path / "missing"), cwd=tmp_path)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "git worktree" in combined or "not a git" in combined or "missing" in combined.lower()


def test_init_fails_when_target_is_nested_inside_git_repo(tmp_path: Path) -> None:
    parent = seed_repo(tmp_path / "parent-repo")
    nested = parent / "nested" / "child"
    nested.mkdir(parents=True)
    result = yasdef("init", str(nested), cwd=tmp_path)
    assert result.returncode != 0


def test_init_bootstraps_existing_git_root(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "worker-repo")
    result = yasdef("init", str(repo), cwd=tmp_path)
    assert result.returncode == 0, result.stderr

    asdlc = repo / ".asdlc_worker"
    assert (asdlc / "asdlc_worker.yaml").is_file()
    assert (asdlc / "blocker_log.md").is_file()
    assert (asdlc / "decisions.md").is_file()
    assert (asdlc / "history.md").is_file()
    assert (asdlc / "open_questions.md").is_file()
    assert (asdlc / "user_review.md").is_file()

    assert (asdlc / "golden_examples").is_dir()
    assert sorted(path.name for path in (asdlc / "golden_examples").iterdir()) == [
        "blocker_log_GOLDEN_EXAMPLE.md",
        "decisions_GOLDEN_EXAMPLE.md",
        "history_GOLDEN_EXAMPLE.md",
        "open_questions_GOLDEN_EXAMPLE.md",
        "user_review_GOLDEN_EXAMPLE.md",
    ]
    assert (asdlc / "templates").is_dir()
    assert (asdlc / "setup").is_dir()
    # logs/ is lazy-created on first phase run; not present at init time
    assert not (asdlc / "scripts").exists(), ".asdlc_worker/scripts must not be created"

    for prefix in PREFIXES:
        for skill in SKILL_NAMES:
            _assert_skill_files(repo, prefix, skill)

    for cmd in ("audit.md", "design.md", "plan.md", "implementation.md", "user-review.md"):
        assert (repo / ".claude" / "commands" / "yasdef" / cmd).is_file()

    # asdlc_worker.yaml records the resolved root
    binding_text = (asdlc / "asdlc_worker.yaml").read_text()
    assert str(repo.resolve()) in binding_text

    # committed on a work branch
    assert (
        git("branch", "--show-current", cwd=repo).stdout.strip() == "init_yasdef_worker"
    )
    tracked = git("ls-tree", "-r", "--name-only", "HEAD", cwd=repo).stdout
    # Core ledger files committed
    assert ".asdlc_worker/asdlc_worker.yaml" in tracked
    assert ".asdlc_worker/blocker_log.md" in tracked
    # Skill files are excluded from git (via .git/info/exclude); not committed
    assert ".codex/skills/yasdef-worker-design/SKILL.md" not in tracked

    # install_manifest.yaml written
    assert (asdlc / "install_manifest.yaml").is_file()


def test_init_skill_prefixes_rewritten_in_skill_md(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "prefix-repo")
    yasdef("init", str(repo), cwd=tmp_path)

    for prefix in PREFIXES:
        skill_md = repo / prefix / "skills" / "yasdef-worker-design" / "SKILL.md"
        content = skill_md.read_text()
        assert f"{prefix}/skills/" in content, f"prefix not rewritten in {skill_md}"


def test_init_reinit_from_mainline_succeeds(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "idempotent-repo")
    yasdef("init", str(repo), cwd=tmp_path)
    # Re-init requires being on main/master first
    git("checkout", "master", cwd=repo)
    result2 = yasdef("init", str(repo), cwd=tmp_path)
    assert result2.returncode == 0, result2.stderr
    assert (repo / ".asdlc_worker" / "asdlc_worker.yaml").is_file()


def test_init_does_not_overwrite_seed_only_ledger_on_reinstall(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "seed-only-repo")
    yasdef("init", str(repo), cwd=tmp_path)

    ledger = repo / ".asdlc_worker" / "decisions.md"
    original = ledger.read_text()
    ledger.write_text(original + "\n# operator edit\n")
    edited = ledger.read_text()

    yasdef("init", str(repo), cwd=tmp_path)
    assert ledger.read_text() == edited, "seed-only ledger must not be overwritten on reinstall"


def test_init_feature_meta_sync_excluded(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "exclude-repo")
    yasdef("init", str(repo), cwd=tmp_path)
    exclude = (repo / ".git" / "info" / "exclude").read_text()
    assert ".asdlc_worker/feature_meta_sync.yaml" in exclude


def test_init_skill_dirs_in_git_exclude(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "skill-exclude-repo")
    yasdef("init", str(repo), cwd=tmp_path)
    exclude = (repo / ".git" / "info" / "exclude").read_text()
    for prefix in PREFIXES:
        for skill in SKILL_NAMES:
            assert f"{prefix}/skills/{skill}" in exclude


def test_init_does_not_create_overmind_runtime_mirror_files(tmp_path: Path) -> None:
    repo = seed_repo(tmp_path / "no-mirror-repo")
    yasdef("init", str(repo), cwd=tmp_path)
    asdlc = repo / ".asdlc_worker"
    # Legacy bash installer created these; Python installer must not
    assert not (asdlc / "AI_DEVELOPMENT_PROCESS.md").exists()
    assert not (asdlc / "scripts").exists()
