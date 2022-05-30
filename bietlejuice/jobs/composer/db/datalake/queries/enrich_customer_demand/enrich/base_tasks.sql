WITH base_crm_analyst_info AS (
  SELECT DISTINCT
    turf.id_task,
    ac.id_assignee AS id_agent,
    action_type
  FROM
    datalake_crm_tasks_flows.tasks_users_resolutions_flow turf
  JOIN
    datalake_ebdb_user.user du
      ON du.id = turf.id_assignee
  JOIN
    datalake_gsheets_clean.agents_control ac
      ON ac.email = du.email
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
    tarf.type,
    5 AS sla_target,
    tarf.ts_started,
    tarf.ts_completed
  FROM 
    datalake_crm_tasks_flows.tasks_actions_resolutions_flow tarf
  JOIN
    last_updated_task lut
      ON tarf.id_task = lut.id_task
      AND DATE(CONCAT(year, '-', month, '-', day)) = lut.dt_last_updated
  LEFT JOIN
    base_crm_analyst_info bca
      ON tarf.id_task = bca.id_task
  WHERE
    tarf.type IN (
      'RevisarPagamentosRescisao',
      'RescisaoPreVigencia'
    )
    AND bca.action_type = 'CREATE'
    AND tarf.ts_started >= '2021-01-01'
),
ticket_tasks AS (
  WITH ticket_started AS (
    SELECT
      e.id_ticket,
      e.id_agent,
      e.department,
      e.csat_score,
      e.is_solved,
      e.tags,
      e.contact_theme_detail_tag,
      e.contact_theme_tag,
      CASE
        WHEN 
          DATE(GET_JSON_OBJECT(REPLACE(REPLACE(tf.custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ')) IS NOT NULL
          AND DATE(GET_JSON_OBJECT(REPLACE(REPLACE(tf.custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ')) >= e.ts_ticket_started 
          AND DATE(GET_JSON_OBJECT(REPLACE(REPLACE(tf.custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ')) < ts_ticket_solved
        THEN CAST(GET_JSON_OBJECT(REPLACE(REPLACE(tf.custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ') AS TIMESTAMP)
        ELSE e.ts_ticket_started  
      END AS ts_started,
      ts_ticket_solved AS ts_completed,
      ts_ticket_ended AS ts_closed,
      ts_csat_first_response AS ts_csat_answer
    FROM
      datalake_customer_support.email e
    LEFT JOIN
      datalake_zendesk_ticket_funnels.ticket_funnel tf
        ON e.id_ticket = tf.id_ticket
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
    t.department AS type,
    t.csat_score,
    t.is_solved,
    CASE 
      WHEN t.department IN ('Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]') THEN 21
      ELSE COALESCE(tds.sla_in_days,ts.sla_in_days, ujst.sla_in_days, tst.sla) 
    END AS sla_target,
    t.ts_started,
    t.ts_completed,
    t.ts_closed,
    t.ts_csat_answer
  FROM
    ticket_started t
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON t.department = dc.department
  LEFT JOIN
    unique_theme_detail_sla_target tds
      ON dc.journey_step = tds.journey_step
      AND t.contact_theme_detail_tag = tds.taxonomy_tag
      AND NOT t.tags LIKE '%orçamentação_realizada%'
      AND DATE(t.ts_started) = tds.dt_reference
  LEFT JOIN
    unique_theme_sla_target ts
      ON dc.journey_step = ts.journey_step
      AND t.contact_theme_detail_tag = ts.taxonomy_tag
      AND NOT t.tags LIKE '%orçamentação_realizada%'
      AND DATE(t.ts_started) = ts.dt_reference
  LEFT JOIN
    unique_journey_sla_target ujst
      ON dc.journey_step = ujst.journey_step
      AND NOT t.tags LIKE '%orçamentação_realizada%'
      AND DATE(t.ts_started) = ujst.dt_reference
  LEFT JOIN
    datalake_gsheets_clean.tag_sla_target tst
      ON dc.journey_step = tst.journey
      AND t.tags LIKE '%orçamentação_realizada%'
      AND t.tags LIKE CONCAT('%', tst.tag, '%')
      AND t.ts_started BETWEEN tst.dt_start AND COALESCE(tst.dt_end, NOW())
  WHERE
    t.ts_started >= '2021-01-01'
    AND t.tags NOT LIKE '%robotserviceaccount02%'
    AND (
      (t.department = 'Midias Ops [POS] [BACK]' AND (t.tags LIKE '%escalar_back_midias%' OR t.tags LIKE '%escalar_ouvidoria_hard_cases%'))
      OR t.department <> 'Midias Ops [POS] [BACK]'
    )
    AND (
      (t.department = 'Offboarding Reparos [OFF] [POS] [BACK]' AND t.tags LIKE '%orçamentação_realizada%')
      OR t.department <> 'Offboarding Reparos [OFF] [POS] [BACK]'
    )
)
SELECT
  id_task,
  id_agent,
  type,
  sla_target,
  NULL AS csat_score,
  NULL AS is_solved,
  ts_started,
  ts_completed,
  ts_completed AS ts_closed,
  NULL AS ts_csat_answer
FROM
  crm_tasks
UNION ALL
SELECT
  id_task,
  id_agent,
  type,
  sla_target,
  csat_score,
  is_solved,
  ts_started,
  ts_completed,
  ts_closed,
  ts_csat_answer
FROM
  ticket_tasks