WITH issues AS (
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
        GET_JSON_OBJECT(fields,'$.project.key') AS project_key,
        GET_JSON_OBJECT(fields, '$.project.name') AS project_name,
        GET_JSON_OBJECT(fields,'$.summary') AS summary,
        GET_JSON_OBJECT(fields,'$.issuetype.name') AS issue_type_name,
        GET_JSON_OBJECT(fields,'$.description.content[0].content[0].text') AS issue_description,
        GET_JSON_OBJECT(fields, '$.priority.name') AS priority,
        GET_JSON_OBJECT(fields, '$.customfield_10200.requestType.name') AS request_type_name,
        -- Assignee
        GET_JSON_OBJECT(fields, '$.assignee.displayName') AS assignee_name,
        GET_JSON_OBJECT(fields, '$.assignee.emailAddress') AS assignee_email,
        -- Reporter
        GET_JSON_OBJECT(fields, '$.reporter.displayName') AS reporter_name,
        GET_JSON_OBJECT(fields, '$.reporter.emailAddress') AS reporter_email,
        -- Creator
        GET_JSON_OBJECT(fields, '$.creator.displayName') AS creator_name,
        GET_JSON_OBJECT(fields, '$.creator.emailAddress') AS creator_email,
        -- form questions
        GET_JSON_OBJECT(fields, '$.customfield_22689.value') AS form_response_issue_module, --Em que módulo está o problema? [Form S&S Dados] Módulo
        GET_JSON_OBJECT(fields, '$.customfield_25836.value') AS form_response_issue_type, -- Qual o tipo de problema? [Form S&S Dados] Atualizaçao de dado defazado - Prolema
        GET_JSON_OBJECT(fields, '$.customfield_22600.value') AS form_response_integration_type, -- [Form S&S Dados] Integração/Atualização Dados > Jornada
        GET_JSON_OBJECT(fields, '$.customfield_22602.value') AS form_response_data_model_issue, -- [Form S&S Dados] Problemas na modelagem dos dados > Jornada
        GET_JSON_OBJECT(fields, '$.customfield_22692.value') AS form_response_dag, -- [Form S&S Dados] Em qual dag está o problema?
        GET_JSON_OBJECT(fields, '$.customfield_25333.value') AS form_response_data_integration, -- [Form S&S Dados] Integração de dados
        GET_JSON_OBJECT(fields, '$.customfield_22605.value') AS form_response_atento_issue, -- [Form S&S Dados] Atento > Problema
        GET_JSON_OBJECT(fields, '$.customfield_22604.value') AS form_response_birdie_issue, -- [Form S&S Dados] Birdie > Problema
        -- form details
        GET_JSON_OBJECT(fields, '$.customfield_12221.value') AS line,
        FROM_JSON(GET_JSON_OBJECT(fields, '$.customfield_11681'), 'ARRAY<STRING>') AS initial_squad,
        GET_JSON_OBJECT(fields, '$.customfield_11356.value') AS squad,
        GET_JSON_OBJECT(fields, '$.customfield_19925') AS previous_status,
        FROM_JSON(GET_JSON_OBJECT(fields, '$.customfield_10727'), 'ARRAY<STRING>') AS issue_sub_categorization,
        FROM_JSON(GET_JSON_OBJECT(fields, '$.labels'), 'ARRAY<STRING>') AS labels,
        FROM_JSON(
            GET_JSON_OBJECT(fields, '$.customfield_10201'),
            'ARRAY<STRUCT<
                accountId:STRING,
                displayName:STRING
            >>'
        ) AS request_participants,
        FROM_JSON(GET_JSON_OBJECT(fields, '$.customfield_19832'), 'ARRAY<STRING>')  AS b_labels,
        GET_JSON_OBJECT(fields, '$.customfield_19688.value') AS b_final_resolution,
        GET_JSON_OBJECT(fields, '$.customfield_25199') AS aura_invalid_agent_rule_applied,
        GET_JSON_OBJECT(fields, '$.customfield_25244') AS aura_invalid_agent_status,
        -- custom cols
        CAST(GET_JSON_OBJECT(fields, '$.customfield_10200.requestType.id') AS BIGINT) = 9228 AS is_data_ai_team_bug,
        -- comments and attachments
        INT(GET_JSON_OBJECT(fields,'$.comment.total')) AS total_comments,
        SIZE(FROM_JSON(GET_JSON_OBJECT(fields, '$.attachment'), "ARRAY<STRING>")) AS total_attachments,
        -- time_to_first_response
        TIMESTAMP(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'), '$[0].startTime.iso8601')) AS ts_sla_first_response_started,
        TIMESTAMP(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'), '$[0].stopTime.iso8601')) AS ts_sla_first_response_completed,
        TIMESTAMP(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'), '$[0].breachTime.iso8601')) AS ts_sla_first_response_breach_limit,
        CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'), '$[0].breached') AS BOOLEAN) AS is_sla_first_response_breached,
        CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'), '$[0].goalDuration.millis') AS BIGINT)/3600000 AS sla_first_response_goal_hours,
        CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'), '$[0].elapsedTime.millis') AS BIGINT)/3600000 AS sla_first_response_elapsed_hours,
        CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10222.completedCycles'), '$[0].remainingTime.millis') AS BIGINT)/3600000 AS sla_first_response_remaining_hours,
        -- time_to_resolution
        TIMESTAMP(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'), '$[0].startTime.iso8601')) AS ts_sla_resolution_started,
        TIMESTAMP(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'), '$[0].stopTime.iso8601')) AS ts_sla_resolution_completed,
        TIMESTAMP(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'), '$[0].breachTime.iso8601')) AS ts_sla_resolution_breach_limit,
        CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'), '$[0].breached') AS BOOLEAN) AS is_sla_resolution_breached,
        CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'), '$[0].goalDuration.millis') AS BIGINT)/3600000 AS sla_resolution_goal_hours,
        CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'), '$[0].elapsedTime.millis') AS BIGINT)/3600000 AS sla_resolution_elapsed_hours,
        CAST(GET_JSON_OBJECT(GET_JSON_OBJECT(fields, '$.customfield_10221.completedCycles'), '$[0].remainingTime.millis') AS BIGINT)/3600000 AS sla_resolution_remaining_hours,
        -- status
        GET_JSON_OBJECT(fields,'$.status.name') AS current_status,
        GET_JSON_OBJECT(fields, '$.status.statusCategory.name') AS current_status_category,
        TIMESTAMP(GET_JSON_OBJECT(fields, '$.customfield_10200.currentStatus.statusDate.iso8601')) AS ts_current_status,
        TIMESTAMP(GET_JSON_OBJECT(fields, '$.statuscategorychangedate')) AS ts_current_status_category_changed,
        TIMESTAMP(GET_JSON_OBJECT(fields, '$.resolutiondate')) AS ts_resolved,
        TIMESTAMP(GET_JSON_OBJECT(fields, '$.created')) AS ts_created,
        TIMESTAMP(GET_JSON_OBJECT(fields, '$.updated')) AS ts_updated,
        MAKE_DATE(year, month, day) AS ts_load,
        YEAR(TIMESTAMP(GET_JSON_OBJECT(fields, '$.created'))) AS year,
        MONTH(TIMESTAMP(GET_JSON_OBJECT(fields, '$.created'))) AS month,
        DAY(TIMESTAMP(GET_JSON_OBJECT(fields, '$.created'))) AS day
    FROM
        datalake_jira_clean.issues
    WHERE
        INT(GET_JSON_OBJECT(fields, '$.project.id')) = 10400
        AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY key ORDER BY MAKE_DATE(year, month, day) DESC)
),
comments AS (
    WITH full_comments AS (
        SELECT
            c.id_issue,
            ARRAY_JOIN(
                COLLECT_LIST("[" || c.ts_created || " - " || ua.name || "]: " || c.comment) OVER (
                    PARTITION BY c.id_issue
                    ORDER BY c.ts_created, c.ts_updated, c.ts_load
                ),
                '\n'
            ) AS comments,
            c.ts_created,
            c.ts_updated,
            c.ts_load
        FROM
            datalake_jira_bugs.comments AS c
        JOIN
            issues AS i
                ON i.id_issue = c.id_issue
        JOIN
            datalake_jira_bugs.user_account AS ua
                ON ua.id_account = c.id_author_account
    )
    SELECT
        fc.id_issue,
        fc.comments
    FROM  
        full_comments AS fc
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY fc.id_issue ORDER BY fc.ts_created DESC, fc.ts_updated DESC, fc.ts_load DESC)
),
attachments AS (
    WITH full_attachments AS (
        SELECT
            a.id_issue,
            ARRAY_JOIN(
                COLLECT_LIST("[" || a.ts_created || " - " || ua.name || "]: " || a.file_name) OVER (
                    PARTITION BY a.id_issue
                    ORDER BY a.ts_created, a.ts_updated
                ),
                '\n'
            ) AS attachments,
            a.ts_created,
            a.ts_updated
        FROM
            datalake_jira_bugs.attachments AS a
        JOIN
            issues AS i
                ON i.id_issue = a.id_issue
        JOIN
            datalake_jira_bugs.user_account AS ua
                ON ua.id_account = a.id_author_account
    )
    SELECT
        fa.id_issue,
        fa.attachments
    FROM  
        full_attachments AS fa
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY fa.id_issue ORDER BY fa.ts_created DESC, fa.ts_updated DESC)
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
        WHEN i.ts_sla_first_response_completed IS NOT NULL 
            AND i.is_sla_first_response_breached IS FALSE
            THEN 'SLA cumprido'
        WHEN i.ts_sla_first_response_completed IS NOT NULL 
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
        WHEN i.ts_sla_resolution_completed IS NOT NULL 
            AND i.is_sla_resolution_breached IS FALSE
            THEN 'SLA cumprido'
        WHEN i.ts_sla_resolution_completed IS NOT NULL 
            AND i.is_sla_resolution_breached IS TRUE
            THEN 'SLA estourado'
        WHEN i.ts_sla_resolution_completed IS NULL 
            AND i.is_sla_resolution_breached IS FALSE
            THEN 'Em andamento - dentro do SLA'
        WHEN i.ts_sla_resolution_completed IS NULL 
            AND i.is_sla_resolution_breached IS TRUE
            THEN 'Em andamento - SLA estourado'
        ELSE 'Sem SLA'
    END AS sla_resolution_status,
    ROUND(IF(i.ts_sla_first_response_completed IS NOT NULL, i.sla_first_response_elapsed_hours, NULL), 2) AS first_response_hours,
    ROUND(CASE
        WHEN i.ts_sla_first_response_completed IS NOT NULL
            AND i.is_sla_first_response_breached IS TRUE
            THEN i.sla_first_response_elapsed_hours - i.sla_first_response_goal_hours
        ELSE 0
    END, 2) AS first_response_delay_hours,
    ROUND(IF(i.ts_sla_resolution_completed IS NOT NULL, i.sla_resolution_elapsed_hours, NULL), 2) AS sla_resolution_hours,
    ROUND(CASE
        WHEN i.ts_sla_resolution_completed IS NOT NULL
            AND i.is_sla_resolution_breached IS TRUE
            THEN i.sla_resolution_elapsed_hours - i.sla_resolution_goal_hours
        ELSE 0
    END, 2) AS resolution_delay_hours,
    i.ts_sla_first_response_completed IS NOT NULL AND i.is_sla_first_response_breached IS FALSE AS is_sla_first_response_agreed,
    i.ts_sla_resolution_completed IS NOT NULL AND i.is_sla_resolution_breached IS FALSE AS is_sla_resolution_agreed,
    i.is_data_ai_team_bug,
    i.current_status = "Invalid" AS is_invalid_bug,
    i.current_status = "Triage" AS is_in_triage,
    i.current_status = "NEED MORE INFO" AS is_need_more_info,
    i.current_status = "Under investigation" AS is_under_investigation,
    i.current_status = "Close - Resolved" AS is_resolved,
    i.current_status IN ("Close - Not Resolved", "Close - Resolved") AS is_closed,
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
FROM 
    issues AS i
LEFT JOIN
    comments AS c
        ON i.id_issue = c.id_issue
LEFT JOIN
    attachments AS a
        ON i.id_issue = a.id_issue