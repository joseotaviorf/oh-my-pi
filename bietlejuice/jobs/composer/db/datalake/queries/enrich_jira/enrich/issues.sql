WITH record_selection AS (
    SELECT 
        key AS id_issue,
        GET_JSON_OBJECT(fields,'$.parent.key') AS id_parent_issue,
        GET_JSON_OBJECT(fields, '$.project.id') AS id_project,
        GET_JSON_OBJECT(fields,'$.summary') AS summary,
        GET_JSON_OBJECT(fields,'$.description') AS issue_description,
        GET_JSON_OBJECT(fields, '$.project.name') AS project_name,
        GET_JSON_OBJECT(fields,'$.issuetype.name') AS issue_type,
        GET_JSON_OBJECT(fields,'$.status.name') AS current_status,
        GET_JSON_OBJECT(fields, '$.assignee.displayName') AS assignee,
        GET_JSON_OBJECT(fields, '$.reporter.displayName') AS reporter,
        GET_JSON_OBJECT(fields, '$.priority.name') AS priority,
        GET_JSON_OBJECT(fields, '$.resolution.name') AS resolution,
        GET_JSON_OBJECT(fields, '$.customfield_11195.value') AS root_cause_resolution,
        GET_JSON_OBJECT(fields, '$.customfield_11194.value') AS incident_category,
        GET_JSON_OBJECT(fields, '$.customfield_12078.value') AS incident_owner,
        FROM_JSON(GET_JSON_OBJECT(fields, '$.labels'), 'array<string>') AS labels,
        FROM_JSON(
            GET_JSON_OBJECT(fields, '$.customfield_10115'), 
            'array<struct<
                id:int,
                name:string,
                state:string,
                boardId:int,
                goal:string,
                startDate:timestamp,
                endDate:timestamp,
                completeDate:timestamp
            >>'
        ) AS cycles,
        CAST(GET_JSON_OBJECT(fields, '$.customfield_10117') AS DOUBLE) AS story_points,
        GET_JSON_OBJECT(fields, '$.customfield_10400[0].value') IS NOT NULL AS is_flagged,
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
    id_project,
    summary,
    issue_description,
    project_name,
    issue_type,
    current_status,
    assignee,
    reporter,
    priority,
    resolution,
    root_cause_resolution,
    incident_category,
    incident_owner,
    FILTER(cycles, c -> c.id = ARRAY_MAX(cycles.id))[0] AS last_cycle,
    labels,
    cycles,
    story_points,
    is_flagged,
    ts_created,
    ts_updated,
    ts_resolved
FROM
    record_selection
WHERE
    row_num = 1