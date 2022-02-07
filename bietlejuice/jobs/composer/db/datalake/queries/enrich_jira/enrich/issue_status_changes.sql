WITH issue_change AS (
    SELECT DISTINCT 
        key, 
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(change_log,'$.histories'), 'array<string>')) AS histories, 
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(histories,'$.items'), 'array<string>')) AS items
    FROM datalake_jira_clean.issues
)
SELECT 
    key AS id_issue, 
    CAST(GET_JSON_OBJECT(histories,'$.id') AS bigint) AS id_change,
    GET_JSON_OBJECT(histories,'$.author.accountId') AS id_author,
    GET_JSON_OBJECT(items,'$.field') AS field,
    GET_JSON_OBJECT(items,'$.fieldtype') AS field_type,
    GET_JSON_OBJECT(items,'$.fromString') AS from_queue,
    GET_JSON_OBJECT(items,'$.toString') AS to_queue,
    GET_JSON_OBJECT(histories,'$.author.emailAddress') AS author_email,
    GET_JSON_OBJECT(histories,'$.author.displayName') AS author_name,
    CAST(GET_JSON_OBJECT(histories,'$.author.active') AS boolean) AS is_author_active,
    CAST(REPLACE(GET_JSON_OBJECT(histories,'$.created'), '-0300', '') AS timestamp) AS ts_updated
FROM issue_change
WHERE GET_JSON_OBJECT(items,'$.field') = 'status'
