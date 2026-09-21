import subprocess

import pytest

from scripts.services.git_service import GitService


def _init_repo(path, branch: str = "master") -> None:
    subprocess.run(["git", "init", "-q", "-b", branch, str(path)], check=True)
    subprocess.run(["git", "-C", str(path), "config", "user.email", "t@t"], check=True)
    subprocess.run(["git", "-C", str(path), "config", "user.name", "t"], check=True)


def _commit(path, name: str, content: str = "x\n") -> None:
    (path / name).write_text(content, encoding="utf-8")
    subprocess.run(["git", "-C", str(path), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(path), "commit", "-qm", name], check=True)


def test_get_modified_files_from_diff_returns_statuses(tmp_path, monkeypatch) -> None:
    _init_repo(tmp_path)
    _commit(tmp_path, "base.txt")
    subprocess.run(
        ["git", "-C", str(tmp_path), "checkout", "-q", "-b", "feat"], check=True
    )
    _commit(tmp_path, "added.txt")
    monkeypatch.chdir(tmp_path)
    # Act
    assert GitService().get_modified_files_from_diff("master", "HEAD") == {
        "added.txt": "A"
    }


def test_get_modified_files_from_diff_raises_on_unresolvable_ref(
    tmp_path, monkeypatch
) -> None:
    _init_repo(tmp_path)
    _commit(tmp_path, "base.txt")
    monkeypatch.chdir(tmp_path)
    fetched = []
    monkeypatch.setattr(
        "scripts.services.git_service.fetch_diff_base",
        lambda from_ref: fetched.append(from_ref),
    )
    # Act / Assert — an unresolvable diff base must not look like "no changes";
    # every caller treats an empty dict as "nothing to validate" and skips.
    with pytest.raises(subprocess.CalledProcessError):
        GitService().get_modified_files_from_diff("origin/development", "HEAD")
    assert fetched == ["origin/development"]
