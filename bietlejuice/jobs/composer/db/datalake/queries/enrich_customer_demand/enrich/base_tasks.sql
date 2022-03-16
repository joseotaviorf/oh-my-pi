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
    tarf.type = 'RevisarPagamentosRescisao'
    AND bca.action_type = 'CREATE'
    AND tarf.ts_started >= '2021-01-01'
),
ticket_tasks AS (
  WITH ticket_started AS (
    SELECT
      e.id_ticket,
      e.id_agent,
      e.department,
      e.tags,
      e.contact_theme_detail_tag,
      e.contact_theme_tag,
      CASE
        WHEN 
          DATE(GET_JSON_OBJECT(REPLACE(REPLACE(tf.custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ')) IS NOT NULL
          AND DATE(GET_JSON_OBJECT(REPLACE(REPLACE(tf.custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ')) >= e.ts_ticket_started 
        THEN CAST(GET_JSON_OBJECT(REPLACE(REPLACE(tf.custom_fields, '[', ''), ']', ''),'$.Data Orçamentação realizada ') AS TIMESTAMP)
        ELSE e.ts_ticket_started  
      END AS ts_started,
      ts_ticket_solved AS ts_completed
    FROM
      datalake_customer_support.email e
    LEFT JOIN
      datalake_zendesk_ticket_funnels.ticket_funnel tf
        ON e.id_ticket = tf.id_ticket
  ),
  unique_taxonomy_sla_target AS (
    SELECT DISTINCT
      journey_step,
      contact_theme_detail_tag AS taxonomy_tag,
      sla_in_days,
      EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE(NOW())))) AS dt_reference
    FROM
      datalake_gsheets_clean.taxonomy_sla
    WHERE
      dt_target_invalidated IS NULL
    UNION ALL
    SELECT
      journey_step,
      contact_theme_tag AS taxonomy_tag,
      MIN(sla_in_days) AS sla_in_days,
      EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE(NOW())))) AS dt_reference
    FROM
      datalake_gsheets_clean.taxonomy_sla
    WHERE
      dt_target_invalidated IS NULL
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
    COALESCE(ts.sla_in_days, ujst.sla_in_days, tst.sla) AS sla_target,
    t.ts_started,
    t.ts_completed
  FROM
    ticket_started t
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON t.department = dc.department
  LEFT JOIN
    unique_taxonomy_sla_target ts
      ON dc.journey_step = ts.journey_step
      AND (
        t.contact_theme_detail_tag = ts.taxonomy_tag
        OR (t.contact_theme_detail_tag IS NULL AND t.contact_theme_tag = ts.taxonomy_tag)
      )
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
),
heimdall_tasks AS (
  WITH crm_last_task_updated AS (
    SELECT DISTINCT
      id,
      LAST_VALUE(id_state) OVER(PARTITION BY id ORDER BY DATE(CONCAT(year,'-',month,'-',day)) ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS id_state
    FROM
      datalake_crm.tasks t
  )
  SELECT DISTINCT
    a.id_external_contract AS id_task,
    MAX(COALESCE(bca.id_agent, '-1')) AS id_agent,
    a.type,
    2 AS sla_target,
    DATE_TRUNC('DAY', a.ts_requested) AS ts_started,
    DATE_TRUNC('DAY', a.ts_transition_created) AS ts_completed
  FROM
    datalake_heimdall.activity a
  LEFT JOIN
    crm_last_task_updated crm
        ON a.id = crm.id_state
  LEFT JOIN
    base_crm_analyst_info bca
      ON crm.id = bca.id_task
  LEFT JOIN
    datalake_heimdall.expenses e
      ON e.id_activity = a.id
  WHERE
    a.type = 'TENANT_REFUND_REPAIR'
    AND (bca.id_task IS NULL OR bca.action_type = 'CREATE')
    AND a.ts_requested >= '2021-01-01'
  GROUP BY 1,3,4,5,6
)
SELECT
  id_task,
  id_agent,
  type,
  sla_target,
  ts_started,
  ts_completed
FROM
  crm_tasks
UNION ALL
SELECT
  id_task,
  id_agent,
  type,
  sla_target,
  ts_started,
  ts_completed
FROM
  ticket_tasks
UNION ALL
SELECT
  id_task,
  id_agent,
  type,
  sla_target,
  ts_started,
  ts_completed
FROM
  heimdall_tasks