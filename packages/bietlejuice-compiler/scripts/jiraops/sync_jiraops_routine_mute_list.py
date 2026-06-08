from __future__ import annotations

import os
import sys

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient
from scripts.jiraops.build_jiraops_mute_criteria import BuildJiraOpsMuteCriteria

logger = QuintoAndarLogger("SyncJiraOpsRoutineMuteList")

JIRA_OPS_USERNAME = "JIRA_OPS_USERNAME"
JIRA_OPS_TOKEN = "JIRA_OPS_TOKEN"
JIRA_OPS_CLOUD_ID = "JIRA_OPS_CLOUD_ID"


def main() -> int:
    username = os.environ.get(JIRA_OPS_USERNAME)
    token = os.environ.get(JIRA_OPS_TOKEN)
    cloud_id = os.environ.get(JIRA_OPS_CLOUD_ID)
    if not username or not token or not cloud_id:
        logger.error(
            "Set %s, %s, %s to a JSON object with username, token, cloud_id",
            JIRA_OPS_USERNAME,
            JIRA_OPS_TOKEN,
            JIRA_OPS_CLOUD_ID,
        )
        return 1
    try:
        criteria = BuildJiraOpsMuteCriteria().build_routing_rule_criteria()
        client = JiraOpsClient(
            credentials={"username": username, "token": token, "cloud_id": cloud_id}
        )
        response = client.update_team_routing_rule_criteria(
            criteria=criteria,
        )
        response.raise_for_status()
        logger.info(
            "Synced %s conditions to Jira Ops", len(criteria.get("conditions", []))
        )
        return 0
    except Exception as err:
        logger.error("Failed to sync Jira Ops mute criteria: %s", err)
        return 1


if __name__ == "__main__":
    sys.exit(main())
