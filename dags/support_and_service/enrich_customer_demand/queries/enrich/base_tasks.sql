WITH base_crm_analyst_info AS (
  SELECT DISTINCT
    turf.id_task,
    MD5(a.email) AS id_agent,
    a.email AS agent_email,
    action_type
  FROM
    datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
  INNER JOIN
    datalake_ebdb_user.user AS du
      ON du.id = turf.id_assignee
  INNER JOIN
    datalake_support_users.analysts AS a
      ON a.email = du.email
),
crm_tasks AS (
  WITH last_updated_task AS (
    SELECT
      id_task,
      MAX(DATE(CONCAT(year, '-', month, '-', day))) AS dt_last_updated
    FROM
      datalake_crm_tasks_flows.tasks_actions_resolutions_flow
    GROUP BY 1
  )
  SELECT DISTINCT
    tarf.id_task,
    COALESCE(bca.id_agent, '-1') AS id_agent,
    bca.agent_email,
    tarf.type,
    5 AS sla_target,
    tarf.ts_started,
    tarf.ts_completed
  FROM
    datalake_crm_tasks_flows.tasks_actions_resolutions_flow AS tarf
  INNER JOIN
    last_updated_task AS lut
      ON tarf.id_task = lut.id_task
      AND DATE(CONCAT(year, '-', month, '-', day)) = DATE(lut.dt_last_updated)
  LEFT JOIN
    base_crm_analyst_info AS bca
      ON tarf.id_task = bca.id_task
  WHERE
    tarf.type IN (
      'RevisarPagamentosRescisao',
      'RescisaoPreVigencia'
    )
    AND bca.action_type = 'CREATE'
    AND tarf.ts_started >= '2023-01-01'
),
ticket_tasks AS (
  WITH ticket_started AS (
    SELECT
      id_ticket,
      MD5(agent_email) AS id_agent,
      MD5(
        CONCAT(
          COALESCE(step_tag, ''),
          COALESCE(customer_type_tag, ''),
          COALESCE(client_type, ''),
          COALESCE(request_type, ''),
          COALESCE(contact_motivation_tag, ''),
          COALESCE(contact_theme_tag, ''),
          COALESCE(contact_theme_detail_tag, '')
        )
      ) AS id_taxonomy,
      MD5(department) AS id_main_department,
      MAX(id_user) AS id_user,
      MD5(MAX(tags)) AS id_tags,
      MAX(tags) AS tags,
      agent_email,
      channel,
      department,
      csat_score,
      status,
      is_solved,
      contact_theme_detail_tag,
      contact_theme_tag,
      ts_ticket_started AS ts_zendesk_started,
      CAST(GET_JSON_OBJECT(REPLACE(REPLACE(custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ') AS TIMESTAMP) AS ts_budget,
      CASE
        WHEN
          DATE(GET_JSON_OBJECT(REPLACE(REPLACE(custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ')) IS NOT NULL
          AND DATE(GET_JSON_OBJECT(REPLACE(REPLACE(custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ')) >= ts_ticket_started
          AND DATE(GET_JSON_OBJECT(REPLACE(REPLACE(custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ')) < COALESCE(ts_ticket_solved, NOW())
        THEN CAST(GET_JSON_OBJECT(REPLACE(REPLACE(custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ') AS TIMESTAMP)
        ELSE ts_ticket_started
      END AS ts_started,
      ts_ticket_solved AS ts_completed,
      ts_ticket_ended AS ts_closed,
      ts_csat_first_response AS ts_csat_answer
    FROM
      datalake_customer_support.email
    GROUP BY 1,2,3,4,8,9,10,11,12,13,14,15,16,17,18,19,20,21
  ),
  unique_theme_detail_sla_target AS (
    SELECT DISTINCT
      journey_step,
      contact_theme_detail_tag AS taxonomy_tag,
      sla_in_days,
      EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE(NOW())))) AS dt_reference
    FROM
      datalake_gsheets_clean.taxonomy_sla
    WHERE
      dt_target_invalidated IS NULL
  ),
  unique_theme_sla_target AS (
    WITH exploded_theme_sla AS (
      SELECT
        journey_step,
        contact_theme_tag AS taxonomy_tag,
        sla_in_days,
        EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE(NOW())))) AS dt_reference
      FROM
        datalake_gsheets_clean.taxonomy_sla
      WHERE
        dt_target_invalidated IS NULL
    )
    SELECT
      journey_step,
      taxonomy_tag,
      MIN(sla_in_days) AS sla_in_days,
      dt_reference
    FROM
      exploded_theme_sla
    GROUP BY 1,2,4
  ),
  unique_journey_sla_target AS (
    WITH exploded_journey_taxonomy AS (
      SELECT
        journey_step,
        sla_in_days,
        EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE(NOW())))) AS dt_reference
      FROM
        datalake_gsheets_clean.taxonomy_sla
      WHERE
        dt_target_invalidated IS NULL
    )
    SELECT
      journey_step,
      MIN(sla_in_days) AS sla_in_days,
      dt_reference
    FROM
      exploded_journey_taxonomy
    GROUP BY 1,3
  )
  SELECT DISTINCT
    t.id_ticket AS id_task,
    COALESCE(t.id_agent, '-1') AS id_agent,
    t.id_user,
    t.id_taxonomy,
    t.id_tags,
    t.id_main_department,
    t.channel,
    t.department AS type,
    t.csat_score,
    t.status,
    t.is_solved,
    CASE
      WHEN t.department IN ('Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]') THEN 21
      ELSE COALESCE(tst.sla, tds.sla_in_days, ts.sla_in_days, ujst.sla_in_days)
    END AS sla_target,
    t.agent_email,
    t.ts_zendesk_started,
    t.ts_budget,
    t.ts_started,
    t.ts_completed,
    t.ts_closed,
    t.ts_csat_answer
  FROM
    ticket_started AS t
  LEFT JOIN
    datalake_gsheets_clean.department_control AS dc
      ON t.department = dc.department
  LEFT JOIN
    datalake_gsheets_clean.tag_sla_target AS tst
      ON dc.journey_step = tst.journey
      AND t.tags LIKE CONCAT('%', tst.tag, '%')
      AND t.ts_started BETWEEN tst.dt_start AND COALESCE(tst.dt_end, NOW())
  LEFT JOIN
    unique_theme_detail_sla_target AS tds
      ON dc.journey_step = tds.journey_step
      AND t.contact_theme_detail_tag = tds.taxonomy_tag
      AND DATE(t.ts_started) = tds.dt_reference
  LEFT JOIN
    unique_theme_sla_target AS ts
      ON dc.journey_step = ts.journey_step
      AND t.contact_theme_tag = ts.taxonomy_tag
      AND DATE(t.ts_started) = ts.dt_reference
  LEFT JOIN
    unique_journey_sla_target AS ujst
      ON dc.journey_step = ujst.journey_step
      AND DATE(t.ts_started) = ujst.dt_reference
  WHERE
    t.ts_started >= '2023-01-01'
    AND t.tags NOT LIKE '%robotserviceaccount02%'
    AND (
      (t.department = 'Offboarding Reparos [OFF] [POS] [BACK]' AND (t.tags LIKE '%orçamentação_realizada%'))
      OR t.department <> 'Offboarding Reparos [OFF] [POS] [BACK]'
    )
)
SELECT DISTINCT
  id_task,
  id_agent,
  NULL AS id_user,
  NULL AS id_taxonomy,
  NULL AS id_tags,
  MD5(type) AS id_main_department,
  type,
  sla_target,
  agent_email,
  'crm' AS origin,
  NULL AS status,
  NULL AS csat_score,
  NULL AS is_solved,
  NULL AS ts_zendesk_started,
  NULL AS ts_budget,
  ts_started,
  ts_completed,
  ts_completed AS ts_closed,
  NULL AS ts_csat_answer
FROM
  crm_tasks
UNION ALL
SELECT DISTINCT
  id_task,
  id_agent,
  id_user,
  id_taxonomy,
  id_tags,
  id_main_department,
  type,
  sla_target,
  agent_email,
  CASE
    WHEN channel IN ('email', 'form_faq', 'web', 'other') THEN 'email'
    ELSE channel
  END AS origin,
  status,
  csat_score,
  is_solved,
  ts_zendesk_started,
  ts_budget,
  ts_started,
  ts_completed,
  ts_closed,
  ts_csat_answer
FROM
  ticket_tasks
