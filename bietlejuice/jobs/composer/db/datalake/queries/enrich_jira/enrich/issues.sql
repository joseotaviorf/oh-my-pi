SELECT 
    key AS id_issue,
    GET_JSON_OBJECT(fields,'$.parent.key') AS id_parent_issue,
    GET_JSON_OBJECT(fields,'$.summary') AS summary,
    GET_JSON_OBJECT(fields,'$.description') AS issue_description,
    GET_JSON_OBJECT(fields,'$.issuetype.name') AS issue_type,
    GET_JSON_OBJECT(fields,'$.status.name') AS current_status,
    CAST(REPLACE(GET_JSON_OBJECT(fields,'$.created'), '-0300', '') AS TIMESTAMP) AS ts_created,
    CAST(REPLACE(GET_JSON_OBJECT(fields,'$.resolutiondate'), '-0300', '') AS TIMESTAMP) AS ts_resolved
FROM 
    datalake_jira_clean.issues