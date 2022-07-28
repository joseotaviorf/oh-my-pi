import subprocess
from typing import Dict


class GitService:
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
        diff_branches = f"{from_branch}..{to_branch}"

        bash_command = f"git diff-tree --no-commit-id --name-status -r {diff_branches}"
        process = subprocess.Popen(bash_command.split(), stdout=subprocess.PIPE)
        output, _ = process.communicate()
        decoded_output = output.decode("utf-8").splitlines()

        result = {}
        for entry in decoded_output:
            status, filename = entry.split("\t")
            result[filename] = status

        return result
