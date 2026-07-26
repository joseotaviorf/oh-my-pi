WITH issues AS (
  SELECT
    id_issue,
    id_project,
    id_workspace,
    id_request_type,
    id_issue_type,
    id_assignee_account,
    id_reporter_account,
    id_creator_account,
    id_dag,
    id_line,
    project_key,
    project_name,
    summary,
    issue_type_name,
    issue_description,
    priority,
    request_type_name,
    assignee_name,
    assignee_email,
    reporter_name,
    reporter_email,
    creator_name,
    creator_email,
    form_response_issue_module,
    form_response_issue_type,
    form_response_integration_type,
    form_response_data_model_issue,
    form_response_dag,
    form_response_data_integration,
    form_response_atento_issue,
    form_response_birdie_issue,
    line,
    initial_squad,
    squad,
    previous_status,
    issue_sub_categorization,
    labels,
    request_participants,
    b_labels,
    b_final_resolution,
    aura_invalid_agent_rule_applied,
    aura_invalid_agent_status,
    total_comments,
    total_attachments,
    ts_sla_first_response_started,
    ts_sla_first_response_completed,
    ts_sla_first_response_breach_limit,
    is_sla_first_response_breached,
    sla_first_response_goal_hours,
    sla_first_response_elapsed_hours,
    sla_first_response_remaining_hours,
    ts_sla_resolution_started,
    ts_sla_resolution_completed,
    ts_sla_resolution_breach_limit,
    is_sla_resolution_breached,
    sla_resolution_goal_hours,
    sla_resolution_elapsed_hours,
    sla_resolution_remaining_hours,
    current_status,
    current_status_category,
    ts_current_status,
    ts_current_status_category_changed,
    ts_resolved,
    ts_created,
    ts_updated,
    ts_load,
    year,
    month,
    day
  FROM (
    SELECT
      key AS id_issue,
      CAST(GET_JSON_OBJECT(fields, '$.project.id') AS BIGINT) AS id_project,
      GET_JSON_OBJECT(fields, '$.customfield_25330[0].workspaceId') AS id_workspace,
      CAST(GET_JSON_OBJECT(fields, '$.customfield_10200.requestType.id') AS BIGINT) AS id_request_type,
      GET_JSON_OBJECT(fields, '$.customfield_10200.requestType.issueTypeId') AS id_issue_type,
      GET_JSON_OBJECT(fields, '$.assignee.accountId') AS id_assignee_account,
      GET_JSON_OBJECT(fields, '$.reporter.accountId') AS id_reporter_account,
      GET_JSON_OBJECT(fields, '$.creator.accountId') AS id_creator_account,
      CAST(GET_JSON_OBJECT(fields, '$.customfield_25330[0].objectId') AS BIGINT) AS id_dag,
      CAST(GET_JSON_OBJECT(fields, '$.customfield_25331[0].objectId') AS BIGINT) AS id_line,
      GET_JSON_OBJECT(fields, '$.project.key') AS project_key,
      GET_JSON_OBJECT(fields, '$.project.name') AS project_name,
      GET_JSON_OBJECT(fields, '$.summary') AS summary,
      GET_JSON_OBJECT(fields, '$.issuetype.name') AS issue_type_name,
      GET_JSON_OBJECT(fields, '$.description.content[0].content[0].text') AS issue_description,
      GET_JSON_OBJECT(fields, '$.priority.name') AS priority,
      GET_JSON_OBJECT(fields, '$.customfield_10200.requestType.name') AS request_type_name,
      GET_JSON_OBJECT(fields, '$.assignee.displayName') AS assignee_name, /* Assignee */
      GET_JSON_OBJECT(fields, '$.assignee.emailAddress') AS assignee_email,
      GET_JSON_OBJECT(fields, '$.reporter.displayName') AS reporter_name, /* Reporter */
      GET_JSON_OBJECT(fields, '$.reporter.emailAddress') AS reporter_email,
      GET_JSON_OBJECT(fields, '$.creator.displayName') AS creator_name, /* Creator */
      GET_JSON_OBJECT(fields, '$.creator.emailAddress') AS creator_email,
      GET_JSON_OBJECT(fields, '$.customfield_22689.value') AS form_response_issue_module, /* form questions */ /* Em que módulo está o problema? [Form S&S Dados] Módulo */
      GET_JSON_OBJECT(fields, '$.customfield_25836.value') AS form_response_issue_type, /* Qual o tipo de problema? [Form S&S Dados] Atualizaçao de dado defazado - Prolema */
      GET_JSON_OBJECT(fields, '$.customfield_22600.value') AS form_response_integration_type, /* [Form S&S Dados] Integração/Atualização Dados > Jornada */
      GET_JSON_OBJECT(fields, '$.customfield_22602.value') AS form_response_data_model_issue, /* [Form S&S Dados] Problemas na modelagem dos dados > Jornada */
      GET_JSON_OBJECT(fields, '$.customfield_22692.value') AS form_response_dag, /* [Form S&S Dados] Em qual dag está o problema? */
      GET_JSON_OBJECT(fields, '$.customfield_25333.value') AS form_response_data_integration, /* [Form S&S Dados] Integração de dados */
      GET_JSON_OBJECT(fields, '$.customfield_22605.value') AS form_response_atento_issue, /* [Form S&S Dados] Atento > Problema */
      GET_JSON_OBJECT(fields, '$.customfield_22604.value') AS form_response_birdie_issue, /* [Form S&S Dados] Birdie > Problema */
      GET_JSON_OBJECT(fields, '$.customfield_12221.value') AS line, /* form details */
      FROM_JSON(GET_JSON_OBJECT(fields, '$.customfield_11681'), 'ARRAY<STRING>') AS initial_squad,
      GET_JSON_OBJECT(fields, '$.customfield_11356.value') AS squad,
      GET_JSON_OBJECT(fields, '$.customfield_19925') AS previous_status,
      FROM_JSON(GET_JSON_OBJECT(fields, '$.customfield_10727'), 'ARRAY<STRING>') AS issue_sub_categorization,
      FROM_JSON(GET_JSON_OBJECT(fields, '$.labels'), 'ARRAY<STRING>') AS labels,
      FROM_JSON(
        GET_JSON_OBJECT(fields, '$.customfield_10201'),
        'ARRAY<STRUCT<\n                accountId:STRING,\n                displayName:STRING\n            >>'
      ) AS request_participants,
      FROM_JSON(GET_JSON_OBJECT(fields, '$.customfield_19832'), 'ARRAY<STRING>') AS b_labels,
      GET_JSON_OBJECT(fields, '$.customfield_19688.value') AS b_final_resolution,
      GET_JSON_OBJECT(fields, '$.customfield_25199') AS aura_invalid_agent_rule_applied,
      GET_JSON_OBJECT(fields, '$.customfield_25244') AS aura_invalid_agent_status,
      CAST(GET_JSON_OBJECT(fields, '$.comment.total') AS INT) AS total_comments, /* comments and attachments */
      SIZE(FROM_JSON(GET_JSON_OBJECT(fields, '$.attachment'), 'ARRAY<STRING>')) AS total_attachments,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'),
        '$[0].startTime.iso8601'
      ) AS TIMESTAMP) AS ts_sla_first_response_started, /* time_to_first_response */
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'),
        '$[0].stopTime.iso8601'
      ) AS TIMESTAMP) AS ts_sla_first_response_completed,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'),
        '$[0].breachTime.iso8601'
      ) AS TIMESTAMP) AS ts_sla_first_response_breach_limit,
      CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'), '$[0].breached') AS BOOLEAN) AS is_sla_first_response_breached,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'),
        '$[0].goalDuration.millis'
      ) AS BIGINT) / 3600000 AS sla_first_response_goal_hours,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'),
        '$[0].elapsedTime.millis'
      ) AS BIGINT) / 3600000 AS sla_first_response_elapsed_hours,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'),
        '$[0].remainingTime.millis'
      ) AS BIGINT) / 3600000 AS sla_first_response_remaining_hours,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'),
        '$[0].startTime.iso8601'
      ) AS TIMESTAMP) AS ts_sla_resolution_started, /* time_to_resolution */
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'),
        '$[0].stopTime.iso8601'
      ) AS TIMESTAMP) AS ts_sla_resolution_completed,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'),
        '$[0].breachTime.iso8601'
      ) AS TIMESTAMP) AS ts_sla_resolution_breach_limit,
      CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'), '$[0].breached') AS BOOLEAN) AS is_sla_resolution_breached,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'),
        '$[0].goalDuration.millis'
      ) AS BIGINT) / 3600000 AS sla_resolution_goal_hours,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'),
        '$[0].elapsedTime.millis'
      ) AS BIGINT) / 3600000 AS sla_resolution_elapsed_hours,
      CAST(GET_JSON_OBJECT(
        GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'),
        '$[0].remainingTime.millis'
      ) AS BIGINT) / 3600000 AS sla_resolution_remaining_hours,
      GET_JSON_OBJECT(fields, '$.status.name') AS current_status, /* status */
      GET_JSON_OBJECT(fields, '$.status.statusCategory.name') AS current_status_category,
      CAST(GET_JSON_OBJECT(fields, '$.customfield_10200.currentStatus.statusDate.iso8601') AS TIMESTAMP) AS ts_current_status,
      CAST(GET_JSON_OBJECT(fields, '$.statuscategorychangedate') AS TIMESTAMP) AS ts_current_status_category_changed,
      CAST(GET_JSON_OBJECT(fields, '$.resolutiondate') AS TIMESTAMP) AS ts_resolved,
      CAST(GET_JSON_OBJECT(fields, '$.created') AS TIMESTAMP) AS ts_created,
      CAST(GET_JSON_OBJECT(fields, '$.updated') AS TIMESTAMP) AS ts_updated,
      MAKE_DATE(year, month, day) AS ts_load,
      YEAR(TO_DATE(CAST(GET_JSON_OBJECT(fields, '$.created') AS TIMESTAMP))) AS year,
      MONTH(TO_DATE(CAST(GET_JSON_OBJECT(fields, '$.created') AS TIMESTAMP))) AS month,
      DAY(TO_DATE(CAST(GET_JSON_OBJECT(fields, '$.created') AS TIMESTAMP))) AS day,
      ROW_NUMBER() OVER (PARTITION BY key ORDER BY MAKE_DATE(
        YEAR(TO_DATE(CAST(GET_JSON_OBJECT(fields, '$.created') AS TIMESTAMP))),
        MONTH(TO_DATE(CAST(GET_JSON_OBJECT(fields, '$.created') AS TIMESTAMP))),
        DAY(TO_DATE(CAST(GET_JSON_OBJECT(fields, '$.created') AS TIMESTAMP)))
      ) DESC) AS _w,
      key
    FROM datalake_jira_clean.issues
    WHERE
      CAST(GET_JSON_OBJECT(fields, '$.project.id') AS INT) = 10400
      AND MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  ) AS _t
  WHERE
    1 = _w
), full_comments AS (
  SELECT
    c.id_issue,
    ARRAY_JOIN(
      COLLECT_LIST('[' || c.ts_created || ' - ' || ua.name || ']: ' || c.comment) OVER (PARTITION BY c.id_issue ORDER BY c.ts_created, c.ts_updated, c.ts_load),
      '\n'
    ) AS comments,
    c.ts_created,
    c.ts_updated,
    c.ts_load
  FROM datalake_jira_bugs.comments AS c
  JOIN issues AS i
    ON i.id_issue = c.id_issue
  JOIN datalake_jira_bugs.user_account AS ua
    ON ua.id_account = c.id_author_account
), comments AS (
  SELECT
    id_issue,
    comments
  FROM (
    SELECT
      fc.id_issue,
      fc.comments,
      ROW_NUMBER() OVER (PARTITION BY fc.id_issue ORDER BY fc.ts_created DESC, fc.ts_updated DESC, fc.ts_load DESC) AS _w,
      fc.ts_created,
      fc.ts_updated,
      fc.ts_load
    FROM full_comments AS fc
  ) AS _t
  WHERE
    1 = _w
), full_attachments AS (
  SELECT
    a.id_issue,
    ARRAY_JOIN(
      COLLECT_LIST('[' || a.ts_created || ' - ' || ua.name || ']: ' || a.file_name) OVER (PARTITION BY a.id_issue ORDER BY a.ts_created, a.ts_updated),
      '\n'
    ) AS attachments,
    a.ts_created,
    a.ts_updated
  FROM datalake_jira_bugs.attachments AS a
  JOIN issues AS i
    ON i.id_issue = a.id_issue
  JOIN datalake_jira_bugs.user_account AS ua
    ON ua.id_account = a.id_author_account
), attachments AS (
  SELECT
    id_issue,
    attachments
  FROM (
    SELECT
      fa.id_issue,
      fa.attachments,
      ROW_NUMBER() OVER (PARTITION BY fa.id_issue ORDER BY fa.ts_created DESC, fa.ts_updated DESC) AS _w,
      fa.ts_created,
      fa.ts_updated
    FROM full_attachments AS fa
  ) AS _t
  WHERE
    1 = _w
)
SELECT
  i.id_issue,
  i.id_project,
  i.id_workspace,
  i.id_request_type,
  i.id_issue_type,
  i.id_assignee_account,
  i.id_reporter_account,
  i.id_creator_account,
  i.id_dag,
  i.id_line,
  i.project_key,
  i.project_name,
  i.summary,
  i.issue_type_name,
  i.issue_description,
  i.issue_sub_categorization,
  i.request_type_name,
  i.previous_status,
  i.current_status AS status,
  i.current_status_category AS status_category,
  i.priority,
  i.assignee_name,
  i.assignee_email,
  i.reporter_name,
  i.reporter_email,
  i.creator_name,
  i.creator_email,
  i.line AS line_name,
  i.squad AS squad_name,
  i.initial_squad AS initial_squad_name,
  i.form_response_dag AS dag,
  i.form_response_issue_module AS problem_type,
  i.form_response_issue_type AS problem_description,
  i.form_response_integration_type AS integration_type,
  i.form_response_data_model_issue AS data_model_issue,
  i.form_response_data_integration AS data_integration,
  i.form_response_atento_issue AS atento_issue,
  i.form_response_birdie_issue AS birdie_issue,
  i.b_final_resolution AS final_resolution,
  i.request_participants,
  i.labels,
  i.b_labels,
  i.aura_invalid_agent_rule_applied,
  i.aura_invalid_agent_status,
  i.total_comments,
  c.comments,
  i.total_attachments,
  a.attachments,
  CASE
    WHEN NOT i.ts_sla_first_response_completed IS NULL
    AND i.is_sla_first_response_breached IS FALSE
    THEN 'SLA cumprido'
    WHEN NOT i.ts_sla_first_response_completed IS NULL
    AND i.is_sla_first_response_breached IS TRUE
    THEN 'SLA estourado'
    WHEN i.ts_sla_first_response_completed IS NULL
    AND i.is_sla_first_response_breached IS FALSE
    THEN 'Em andamento - dentro do SLA'
    WHEN i.ts_sla_first_response_completed IS NULL
    AND i.is_sla_first_response_breached IS TRUE
    THEN 'Em andamento - SLA estourado'
    ELSE 'Sem SLA'
  END AS sla_first_response_status,
  CASE
    WHEN NOT i.ts_sla_resolution_completed IS NULL
    AND i.is_sla_resolution_breached IS FALSE
    THEN 'SLA cumprido'
    WHEN NOT i.ts_sla_resolution_completed IS NULL
    AND i.is_sla_resolution_breached IS TRUE
    THEN 'SLA estourado'
    WHEN i.ts_sla_resolution_completed IS NULL AND i.is_sla_resolution_breached IS FALSE
    THEN 'Em andamento - dentro do SLA'
    WHEN i.ts_sla_resolution_completed IS NULL AND i.is_sla_resolution_breached IS TRUE
    THEN 'Em andamento - SLA estourado'
    ELSE 'Sem SLA'
  END AS sla_resolution_status,
  ROUND(
    IF(
      NOT i.ts_sla_first_response_completed IS NULL,
      i.sla_first_response_elapsed_hours,
      NULL
    ),
    2
  ) AS first_response_hours,
  ROUND(
    CASE
      WHEN NOT i.ts_sla_first_response_completed IS NULL
      AND i.is_sla_first_response_breached IS TRUE
      THEN i.sla_first_response_elapsed_hours - i.sla_first_response_goal_hours
      ELSE 0
    END,
    2
  ) AS first_response_delay_hours,
  ROUND(
    IF(NOT i.ts_sla_resolution_completed IS NULL, i.sla_resolution_elapsed_hours, NULL),
    2
  ) AS sla_resolution_hours,
  ROUND(
    CASE
      WHEN NOT i.ts_sla_resolution_completed IS NULL
      AND i.is_sla_resolution_breached IS TRUE
      THEN i.sla_resolution_elapsed_hours - i.sla_resolution_goal_hours
      ELSE 0
    END,
    2
  ) AS resolution_delay_hours,
  NOT i.ts_sla_first_response_completed IS NULL
  AND i.is_sla_first_response_breached IS FALSE AS is_sla_first_response_agreed,
  NOT i.ts_sla_resolution_completed IS NULL
  AND i.is_sla_resolution_breached IS FALSE AS is_sla_resolution_agreed,
  COALESCE(i.id_request_type = 9228 AND i.squad = 'Data', FALSE) AS is_data_ai_team_bug,
  COALESCE(
    i.id_request_type = 9228
    AND i.squad <> 'Data'
    AND ARRAY_CONTAINS(i.initial_squad, 'Data'),
    FALSE
  ) AS is_data_ai_team_redirected,
  i.current_status = 'Invalid' AS is_invalid_bug,
  i.current_status = 'Triage' AS is_in_triage,
  i.current_status = 'NEED MORE INFO' AS is_need_more_info,
  i.current_status = 'Under investigation' AS is_under_investigation,
  i.current_status = 'Close - Resolved' AS is_resolved,
  i.current_status IN ('Close - Not Resolved', 'Close - Resolved') AS is_closed,
  i.ts_sla_first_response_started,
  i.ts_sla_first_response_completed,
  i.ts_sla_first_response_breach_limit,
  i.ts_sla_resolution_started,
  i.ts_sla_resolution_completed,
  i.ts_sla_resolution_breach_limit,
  i.ts_current_status AS ts_status,
  i.ts_current_status_category_changed AS ts_status_category_changed,
  i.ts_resolved,
  i.ts_updated,
  i.ts_created,
  i.ts_load,
  i.year,
  i.month,
  i.day
FROM issues AS i
LEFT JOIN comments AS c
  ON i.id_issue = c.id_issue
LEFT JOIN attachments AS a
  ON i.id_issue = a.id_issue