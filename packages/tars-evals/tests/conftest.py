import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def _litellm_env(monkeypatch):
    monkeypatch.setenv("LITELLM_BASE_URL", "https://example.invalid/v1")
    monkeypatch.setenv("LITELLM_API_KEY", "dummy")


@dataclass
class TmpGitRepo:
    """A throwaway git work tree + bare "origin" remote for diff-resolution tests.

    No test elsewhere in this suite builds a real git repo (everything else
    fakes subprocess/`uv` or uses tmp_path directly) — this is net-new,
    needed because changed_dataset_stems.py's diff-base resolution depends on
    actual git ref/remote mechanics that can't be faithfully faked.
    """

    path: Path
    bare_path: Path

    def _run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", *args], cwd=self.path, check=True, capture_output=True, text=True
        )

    def write(self, relpath: str, content: str = "") -> None:
        target = self.path / relpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def remove(self, relpath: str) -> None:
        (self.path / relpath).unlink()

    def rename(self, src: str, dst: str) -> None:
        target = self.path / dst
        target.parent.mkdir(parents=True, exist_ok=True)
        (self.path / src).rename(target)

    def commit(self, message: str = "test commit") -> str:
        self._run("add", "-A")
        self._run("commit", "-q", "-m", message, "--allow-empty")
        return self.rev_parse("HEAD")

    def push_master(self) -> None:
        self._run("push", "-q", "-f", "origin", "HEAD:refs/heads/master")
        self._run("fetch", "-q", "origin")

    def rev_parse(self, ref: str) -> str:
        return self._run("rev-parse", ref).stdout.strip()


@pytest.fixture
def tmp_git_repo(tmp_path: Path) -> TmpGitRepo:
    work = tmp_path / "work"
    bare = tmp_path / "origin.git"
    work.mkdir()
    subprocess.run(
        ["git", "init", "-q", "-b", "master", str(work)], check=True, capture_output=True
    )
    subprocess.run(
        ["git", "-C", str(work), "config", "user.email", "test@example.com"], check=True
    )
    subprocess.run(["git", "-C", str(work), "config", "user.name", "Test"], check=True)
    subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True, capture_output=True)
    subprocess.run(
        ["git", "-C", str(work), "remote", "add", "origin", str(bare)], check=True
    )

    repo = TmpGitRepo(path=work, bare_path=bare)
    repo.write(".gitkeep")
    repo.commit("initial commit")
    repo.push_master()
    return repo
