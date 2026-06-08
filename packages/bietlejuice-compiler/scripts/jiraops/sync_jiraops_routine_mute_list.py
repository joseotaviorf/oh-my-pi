from __future__ import annotations

import sys

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient
from scripts.jiraops.build_jiraops_mute_criteria import BuildJiraOpsMuteCriteria
from scripts.jiraops.jiraops_credentials import load_jiraops_credentials

logger = QuintoAndarLogger("SyncJiraOpsRoutineMuteList")


def main() -> int:
    try:
        credentials = load_jiraops_credentials()
    except ValueError as err:
        logger.error("%s", err)
        return 1

    try:
        criteria = BuildJiraOpsMuteCriteria().build_routing_rule_criteria()
        client = JiraOpsClient(credentials=credentials)
        response = client.update_team_routing_rule_criteria(criteria=criteria)
        response.raise_for_status()
        logger.info(
            "Synced %s conditions to Jira Ops",
            len(criteria.get("conditions", [])),
        )
        return 0
    except Exception as err:
        logger.error("Failed to sync Jira Ops mute criteria: %s", err)
        return 1


if __name__ == "__main__":
    sys.exit(main())
