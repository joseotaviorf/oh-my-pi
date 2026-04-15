SELECT
    id,
    bill_id AS id_bill,
    source_id AS id_source,
    jira_issue_id AS id_jira_issue,
    version,
    status,
    source,
    reviewed_at AS ts_reviewed,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.bill_reviews
