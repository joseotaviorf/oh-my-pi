SELECT
    id,
    issue_key,
    agent_type,
    issue_type,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.jira_issues