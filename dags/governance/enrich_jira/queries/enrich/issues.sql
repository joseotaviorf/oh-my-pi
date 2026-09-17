WITH record_selection AS (
  SELECT
    id_issue,
    id_parent_issue,
    id_project,
    project_key,
    summary,
    issue_description,
    project_name,
    issue_type,
    current_status,
    current_status_category,
    assignee,
    assignee_account_id,
    reporter,
    owner_person,
    team_name,
    priority,
    criticality,
    resolution,
    incident_category,
    root_cause_resolution,
    incident_owner,
    old_incident_owner,
    dag_owner,
    incident_status,
    sla_affected,
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
    dt_started,
    ts_created,
    ts_updated,
    ts_resolved,
    row_num
  FROM (
    SELECT
      key AS id_issue,
      GET_JSON_OBJECT(fields, '$.parent.key') AS id_parent_issue,
      GET_JSON_OBJECT(fields, '$.project.id') AS id_project,
      GET_JSON_OBJECT(fields, '$.project.key') AS project_key,
      GET_JSON_OBJECT(fields, '$.summary') AS summary,
      GET_JSON_OBJECT(fields, '$.description') AS issue_description,
      GET_JSON_OBJECT(fields, '$.project.name') AS project_name,
      GET_JSON_OBJECT(fields, '$.issuetype.name') AS issue_type,
      GET_JSON_OBJECT(fields, '$.status.name') AS current_status,
      GET_JSON_OBJECT(fields, '$.status.statusCategory.name') AS current_status_category,
      GET_JSON_OBJECT(fields, '$.assignee.displayName') AS assignee,
      GET_JSON_OBJECT(fields, '$.assignee.accountId') AS assignee_account_id,
      GET_JSON_OBJECT(fields, '$.reporter.displayName') AS reporter,
      REGEXP_REPLACE(GET_JSON_OBJECT(fields, '$.customfield_13658'), '[^,a-zA-Z0-9]', '') AS owner_person,
      GET_JSON_OBJECT(fields, '$.customfield_13655.value') AS team_name,
      GET_JSON_OBJECT(fields, '$.priority.name') AS priority,
      GET_JSON_OBJECT(fields, '$.customfield_35959.value') AS criticality,
      CASE
        WHEN GET_JSON_OBJECT(fields, '$.resolution') IS NULL
        AND GET_JSON_OBJECT(fields, '$.status.statusCategory.name') = 'Done'
        THEN 'Done'
        ELSE GET_JSON_OBJECT(fields, '$.resolution.name')
      END AS resolution, /* There was a failure with the automation of the field "resolution", which we can identify when */ /* the issue's status category is done, but there is no resolution. */ /* When that happens, we can set the resolution to "Done" */
      GET_JSON_OBJECT(fields, '$.customfield_11195.value') AS incident_category,
      GET_JSON_OBJECT(fields, '$.customfield_11194.value') AS root_cause_resolution,
      GET_JSON_OBJECT(fields, '$.customfield_31231.value') AS incident_owner,
      GET_JSON_OBJECT(fields, '$.customfield_12078.value') AS old_incident_owner,
      GET_JSON_OBJECT(fields, '$.customfield_30283.value') AS dag_owner,
      GET_JSON_OBJECT(fields, '$.customfield_21698.value') AS incident_status,
      GET_JSON_OBJECT(fields, '$.customfield_12350.value') AS sla_affected,
      FROM_JSON(GET_JSON_OBJECT(fields, '$.labels'), 'array<string>') AS labels,
      FROM_JSON(
        GET_JSON_OBJECT(fields, '$.customfield_10115'),
        'array<struct<\n                id:int,\n                name:string,\n                state:string,\n                boardId:int,\n                goal:string,\n                startDate:timestamp,\n                endDate:timestamp,\n                completeDate:timestamp\n            >>'
      ) AS cycles,
      COALESCE(
        GET_JSON_OBJECT(fields, '$.customfield_16889.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18010.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18039.value')
      ) AS tech_debt_category, /* Tech Debt columns for DPE */
      COALESCE(
        GET_JSON_OBJECT(fields, '$.customfield_16890.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18011.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18040.value')
      ) AS tech_debt_size,
      COALESCE(
        GET_JSON_OBJECT(fields, '$.customfield_18004.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18013.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18034.value')
      ) AS tech_debt_urgency,
      COALESCE(
        GET_JSON_OBJECT(fields, '$.customfield_18005.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18014.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18035.value')
      ) AS tech_debt_user_impact,
      COALESCE(
        GET_JSON_OBJECT(fields, '$.customfield_18006.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18015.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18036.value')
      ) AS tech_debt_blockage,
      COALESCE(
        GET_JSON_OBJECT(fields, '$.customfield_18007.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18012.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18033.value')
      ) AS tech_debt_uncertainty,
      COALESCE(
        GET_JSON_OBJECT(fields, '$.customfield_18008.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18016.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18037.value')
      ) AS tech_debt_cumulativeness,
      COALESCE(
        GET_JSON_OBJECT(fields, '$.customfield_18009.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18017.value'),
        GET_JSON_OBJECT(fields, '$.customfield_18038.value')
      ) AS tech_debt_complexity,
      CAST(GET_JSON_OBJECT(fields, '$.customfield_10117') AS DOUBLE) AS story_points, /* End Tech Debt columns for DPE */
      CAST(GET_JSON_OBJECT(fields, '$.customfield_10508') AS DOUBLE) AS story_points_estimate,
      NOT GET_JSON_OBJECT(fields, '$.customfield_10400[0].value') IS NULL AS is_flagged,
      CAST(GET_JSON_OBJECT(fields, '$.customfield_10503') AS TIMESTAMP) AS dt_started,
      CAST(REPLACE(GET_JSON_OBJECT(fields, '$.created'), '-0300', '') AS TIMESTAMP) AS ts_created,
      GET_JSON_OBJECT(fields, '$.updated') AS ts_updated,
      CAST(REPLACE(
        CASE
          WHEN GET_JSON_OBJECT(fields, '$.resolutiondate') IS NULL
          AND GET_JSON_OBJECT(fields, '$.status.statusCategory.name') = 'Done'
          THEN GET_JSON_OBJECT(fields, '$.statuscategorychangedate')
          ELSE GET_JSON_OBJECT(fields, '$.resolutiondate')
        END,
        '-0300',
        ''
      ) AS TIMESTAMP) AS ts_resolved, /* There was a failure with the automation of the field "resolutiondate", which we can identify when */ /* the issue's status category is done, but there is no resulution date. */ /* When that happens, we can use statuscategorychangedate, which was when the status category was changed to "Done" */
      ROW_NUMBER() OVER (PARTITION BY key ORDER BY GET_JSON_OBJECT(fields, '$.updated') DESC) AS row_num
    FROM datalake_jira_clean.issues
  ) AS _t
  WHERE
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
  assignee_account_id,
  reporter,
  owner_person,
  team_name,
  priority,
  criticality,
  resolution,
  root_cause_resolution,
  incident_category,
  incident_owner,
  old_incident_owner,
  dag_owner,
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
  NOT di.dt_deleted IS NULL AS is_deleted,
  di.dt_deleted,
  dt_started,
  ts_created,
  ts_updated,
  ts_resolved
FROM record_selection AS rs
LEFT JOIN datalake_jira.deleted_issues AS di
  ON rs.id_issue = di.id_issue
