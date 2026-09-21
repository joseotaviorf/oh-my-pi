import subprocess
from typing import Dict

from bietlejuice.ci.ci_diff_ref import fetch_diff_base


class GitService:
    # list of status that indicate files being created or updated
    UPSERT_STATUS_CODES = ["M", "A"]

    def __init__(self):
        self.NEW_OR_MODIFIED_FILE_STATUS = {"A", "M"}

    def get_modified_files_from_diff(
        self, from_branch: str, to_branch: str
    ) -> Dict[str, str]:
        """
        Compares provided branch name with the master branch and gets all the new / modified files and their status

        :param from_branch: The current branch used in comparison. e.g. origin/master
        :param to_branch: The destination branch used in comparison. e.g. HEAD
        :return: A dict of file path to status, according to git diff-tree. For a list of possible statuses
         and their meanings, check git diff-tree --diff-filter documentation under
        https://git-scm.com/docs/git-diff-tree#Documentation/git-diff-tree.txt---diff-filterACDMRTUXB82308203
        :rtype: Dict[str, str]
        """
        # Woodpecker clones one branch. Fetch here so every caller gets the
        # resolved origin/<target> ref, not only the few scripts that remember
        # to call fetch_diff_base themselves.
        fetch_diff_base(from_branch)
        diff_branches = f"{from_branch}...{to_branch}"

        # check=True is load-bearing: an unresolvable ref used to exit non-zero
        # with empty stdout, which every caller read as "no files changed" and
        # silently skipped its validation.
        completed = subprocess.run(
            [
                "git",
                "diff",
                "--no-commit-id",
                "--name-status",
                "--no-renames",
                "-r",
                diff_branches,
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        result = {}
        for entry in completed.stdout.splitlines():
            status, filename = entry.split("\t")
            result[filename] = status

        return result

    def fetch(
        self,
        branch: str,
    ) -> None:
        """
        Fetches the latest changes from the remote repository

        :param branch: The branch to fetch changes from
        """
        bash_command = f"git fetch origin {branch}"
        process = subprocess.Popen(bash_command.split(), stdout=subprocess.PIPE)
        process.communicate()
