WITH record_selection AS (
    SELECT
        key AS id_issue,
        GET_JSON_OBJECT(fields,'$.parent.key') AS id_parent_issue,
        GET_JSON_OBJECT(fields, '$.project.id') AS id_project,
        GET_JSON_OBJECT(fields,'$.project.key') AS project_key,
        GET_JSON_OBJECT(fields,'$.summary') AS summary,
        GET_JSON_OBJECT(fields,'$.description') AS issue_description,
        GET_JSON_OBJECT(fields, '$.project.name') AS project_name,
        GET_JSON_OBJECT(fields,'$.issuetype.name') AS issue_type,
        GET_JSON_OBJECT(fields,'$.status.name') AS current_status,
        GET_JSON_OBJECT(fields, '$.status.statusCategory.name') AS current_status_category,
        GET_JSON_OBJECT(fields, '$.assignee.displayName') AS assignee,
        GET_JSON_OBJECT(fields, '$.reporter.displayName') AS reporter,
        REGEXP_REPLACE(GET_JSON_OBJECT(fields, '$.customfield_13658'),'[^,a-zA-Z0-9]', '') AS owner_person,
        GET_JSON_OBJECT(fields, '$.customfield_13655.value') AS team_name,
        GET_JSON_OBJECT(fields, '$.priority.name') AS priority,
        -- There was a failure with the automation of the field "resolution", which we can identify when
        -- the issue's status category is done, but there is no resolution.
        -- When that happens, we can set the resolution to "Done"
        CASE
            WHEN GET_JSON_OBJECT(fields, '$.resolution') IS NULL
            AND GET_JSON_OBJECT(fields, '$.status.statusCategory.name') = 'Done'
                THEN 'Done'
            ELSE
                GET_JSON_OBJECT(fields, '$.resolution.name')
        END AS resolution,
        GET_JSON_OBJECT(fields, '$.customfield_11195.value') AS incident_category,
        GET_JSON_OBJECT(fields, '$.customfield_11194.value') AS root_cause_resolution,
        GET_JSON_OBJECT(fields, '$.customfield_12078.value') AS incident_owner,
        GET_JSON_OBJECT(fields, '$.customfield_21698.value') AS incident_status,
        GET_JSON_OBJECT(fields, '$.customfield_12350.value') AS sla_affected,
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
        -- Tech Debt columns for DPE
        COALESCE(
            GET_JSON_OBJECT(fields, '$.customfield_16889.value'), 
            GET_JSON_OBJECT(fields, '$.customfield_18010.value'), 
            GET_JSON_OBJECT(fields, '$.customfield_18039.value')) AS tech_debt_category,
        COALESCE(
            GET_JSON_OBJECT(fields, '$.customfield_16890.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18011.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18040.value')) AS tech_debt_size,
        COALESCE(
            GET_JSON_OBJECT(fields, '$.customfield_18004.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18013.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18034.value')) AS tech_debt_urgency,
        COALESCE(
            GET_JSON_OBJECT(fields, '$.customfield_18005.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18014.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18035.value')) AS tech_debt_user_impact,
        COALESCE(
            GET_JSON_OBJECT(fields, '$.customfield_18006.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18015.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18036.value')) AS tech_debt_blockage,
        COALESCE(
            GET_JSON_OBJECT(fields, '$.customfield_18007.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18012.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18033.value')) AS tech_debt_uncertainty,        
        COALESCE(
            GET_JSON_OBJECT(fields, '$.customfield_18008.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18016.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18037.value')) AS tech_debt_cumulativeness,
        COALESCE(
            GET_JSON_OBJECT(fields, '$.customfield_18009.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18017.value'),
            GET_JSON_OBJECT(fields, '$.customfield_18038.value')) AS tech_debt_complexity,
        -- End Tech Debt columns for DPE
        CAST(GET_JSON_OBJECT(fields, '$.customfield_10117') AS DOUBLE) AS story_points,
        CAST(GET_JSON_OBJECT(fields,'$.customfield_10508') AS DOUBLE) AS story_points_estimate,
        GET_JSON_OBJECT(fields, '$.customfield_10400[0].value') IS NOT NULL AS is_flagged,
        CAST(GET_JSON_OBJECT(fields, '$.customfield_10503') AS TIMESTAMP) AS dt_started,
        CAST(REPLACE(GET_JSON_OBJECT(fields,'$.created'), '-0300', '') AS TIMESTAMP) AS ts_created,
        GET_JSON_OBJECT(fields,'$.updated') AS ts_updated,
        -- There was a failure with the automation of the field "resolutiondate", which we can identify when
        -- the issue's status category is done, but there is no resulution date.
        -- When that happens, we can use statuscategorychangedate, which was when the status category was changed to "Done"
        CAST(REPLACE(
            CASE
                WHEN GET_JSON_OBJECT(fields, '$.resolutiondate') IS NULL
                AND GET_JSON_OBJECT(fields, '$.status.statusCategory.name') = 'Done'
                    THEN GET_JSON_OBJECT(fields, '$.statuscategorychangedate')
                ELSE
                    GET_JSON_OBJECT(fields,'$.resolutiondate')
            END, '-0300', ''
        ) AS TIMESTAMP) AS ts_resolved,
        ROW_NUMBER() OVER (PARTITION BY key ORDER BY GET_JSON_OBJECT(fields,'$.updated') DESC) AS row_num
    FROM
        datalake_jira_clean.issues
    QUALIFY
        row_num = 1
)
SELECT
    rs.id_issue,
    id_parent_issue,
    id_project,
    summary,
    issue_description,
    project_name,
    issue_type,
    current_status,
    current_status_category,
    assignee,
    reporter,
    owner_person,
    team_name,
    priority,
    resolution,
    root_cause_resolution,
    incident_category,
    incident_owner,
    incident_status,
    sla_affected,
    FILTER(cycles, c -> c.id = ARRAY_MAX(cycles.id))[0] AS last_cycle,
    labels,
    cycles,
    tech_debt_category,
    tech_debt_size,
    tech_debt_urgency,
    tech_debt_user_impact,
    tech_debt_blockage,
    tech_debt_uncertainty,
    tech_debt_cumulativeness,
    tech_debt_complexity,
    story_points,
    story_points_estimate,
    is_flagged,
    di.dt_deleted IS NOT NULL AS is_deleted,
    di.dt_deleted,
    dt_started,
    ts_created,
    ts_updated,
    ts_resolved
FROM
    record_selection AS rs
LEFT JOIN
    datalake_jira.deleted_issues AS di
        ON rs.id_issue = di.id_issue
