WITH record_selection AS (
    SELECT 
        key AS id_issue,
        GET_JSON_OBJECT(fields,'$.parent.key') AS id_parent_issue,
        GET_JSON_OBJECT(fields,'$.summary') AS summary,
        GET_JSON_OBJECT(fields,'$.description') AS issue_description,
        GET_JSON_OBJECT(fields,'$.issuetype.name') AS issue_type,
        GET_JSON_OBJECT(fields,'$.status.name') AS current_status,
        CAST(REPLACE(GET_JSON_OBJECT(fields,'$.created'), '-0300', '') AS TIMESTAMP) AS ts_created,
        GET_JSON_OBJECT(fields,'$.updated') AS ts_updated,
        CAST(REPLACE(GET_JSON_OBJECT(fields,'$.resolutiondate'), '-0300', '') AS TIMESTAMP) AS ts_resolved,
        ROW_NUMBER() OVER (PARTITION BY key ORDER BY GET_JSON_OBJECT(fields,'$.updated') DESC) AS row_num
    FROM 
        datalake_jira_clean.issues
)
SELECT 
    id_issue,
    id_parent_issue,
    summary,
    issue_description,
    issue_type,
    current_status,
    ts_created,
    ts_updated,
    ts_resolved
FROM
    record_selection
WHERE
    row_num = 1