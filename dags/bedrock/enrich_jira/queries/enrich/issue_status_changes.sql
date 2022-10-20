WITH issue_change AS (
    SELECT DISTINCT 
        key, 
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(change_log,'$.histories'), 'array<string>')) AS histories, 
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(histories,'$.items'), 'array<string>')) AS items
    FROM datalake_jira_clean.issues
), issue_status_change AS (
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
        CAST(REPLACE(GET_JSON_OBJECT(histories,'$.created'), '-0300', '') AS timestamp) AS ts_updated
    FROM issue_change
    WHERE GET_JSON_OBJECT(items,'$.field') = 'status'
), event_order AS (
  SELECT 
    id_issue,
    id_change,
    from_queue,
    to_queue,
    ts_updated,
    row_number() OVER(PARTITION BY id_issue ORDER BY ts_updated) AS event_number
  FROM 
    issue_status_change
  GROUP BY 1,2,3,4,5
), in_out_date AS (
  SELECT 
    eo.id_issue,
    eo.id_change,
    eo.from_queue,
    eo.to_queue,
    eo.event_number,
    ji.ts_created,
    CASE
      WHEN eo.event_number = 1 THEN ji.ts_created
      ELSE eo_before.ts_updated
    END AS ts_income,
    eo.ts_updated AS ts_outcome
  FROM 
    event_order AS eo
  JOIN datalake_jira.issues AS ji 
    ON ji.id_issue = eo.id_issue
  LEFT JOIN event_order AS eo_before
    ON eo.id_issue = eo_before.id_issue
      AND eo.event_number = (eo_before.event_number + 1)
)
SELECT 
  isc.id_issue,
  isc.id_change,
  isc.id_author,
  isc.field,
  isc.field_type,
  iod.from_queue,
  iod.to_queue,
  isc.author_email,
  isc.author_name,
  ROUND((CAST(iod.ts_outcome AS LONG) - CAST(iod.ts_income AS LONG))/60, 2) AS minutes_in_origin_queue,
  isc.ts_updated
FROM
  in_out_date AS iod
JOIN issue_status_change AS isc
    ON isc.id_issue = iod.id_issue
        AND isc.id_change = iod.id_change
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
