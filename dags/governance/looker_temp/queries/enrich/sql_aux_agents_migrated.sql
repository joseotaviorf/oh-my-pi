WITH aux_agents_prep AS (
  SELECT
    CAST(id_user AS BIGINT) AS sk_user_agent,
    dynamic_status AS agent_status,
    CASE
      WHEN dt_activated IS NULL
      THEN NULL
      WHEN NOT dt_activated IS NULL
      THEN TO_TIMESTAMP(REPLACE(CAST(dt_activated AS STRING), '-', ''), 'yyyyMMdd')
    END AS activation,
    CASE
      WHEN dt_week_accreditated IS NULL
      THEN NULL
      WHEN NOT dt_week_accreditated IS NULL
      THEN TO_TIMESTAMP(REPLACE(CAST(dt_week_accreditated AS STRING), '-', ''), 'yyyyMMdd')
    END AS week_accreditation,
    DATE_TRUNC('WEEK', dt_activated) AS week_activation,
    days_since_activation_week AS days_since_activation,
    agent_actual_type AS agent_actual_type,
    CASE
      WHEN dt_last_disqualificated IS NULL
      THEN NULL
      WHEN NOT dt_last_disqualificated IS NULL
      THEN TO_TIMESTAMP(REPLACE(CAST(dt_last_disqualificated AS STRING), '-', ''), 'yyyyMMdd')
    END AS last_disqualification,
    CASE
      WHEN dt_last_disqualification_returned IS NULL
      THEN NULL
      WHEN NOT dt_last_disqualification_returned IS NULL
      THEN TO_TIMESTAMP(REPLACE(CAST(dt_last_disqualification_returned AS STRING), '-', ''), 'yyyyMMdd')
    END AS last_disqualification_return,
    last_disqualification_reason AS disqualification_reason,
    permanent_deaccreditation AS permanently_disqualified,
    CASE
      WHEN dt_last_suspended IS NULL
      THEN NULL
      WHEN NOT dt_last_suspended IS NULL
      THEN TO_TIMESTAMP(REPLACE(CAST(dt_last_suspended AS STRING), '-', ''), 'yyyyMMdd')
    END AS last_suspension,
    CASE
      WHEN dt_last_suspension_returned IS NULL
      THEN NULL
      WHEN NOT dt_last_suspension_returned IS NULL
      THEN TO_TIMESTAMP(REPLACE(CAST(dt_last_suspension_returned AS STRING), '-', ''), 'yyyyMMdd')
    END AS last_suspension_return,
    last_suspension_reason AS suspension_reason
  FROM datalake_airtable.activated
), contract AS (
  SELECT
    id_agent AS agent_id,
    id_user_agent AS id,
    work_contract_name AS contractname,
    ts_work_contract_started AS timestamp,
    RANK() OVER (PARTITION BY id_agent ORDER BY ts_work_contract_started DESC) AS r
  FROM datalake_ebdb_agents.agent_contract
), last_agent_area AS (
  SELECT
    sk_agent,
    CASE
      WHEN area IN ('SBE 01', 'DIA 01')
      THEN 'ABC 02'
      WHEN area IN ('SCA 01', 'STA 01')
      THEN 'ABC 01'
      WHEN area = '-1'
      THEN 'Sem Região Atribuída'
      ELSE area
    END AS ult_area_associada,
    date AS dt_ult_area_associada
  FROM dw_agent.fact_agent_daily_allocations AS fa
  JOIN dw_public.dim_date AS dt
    ON dt.sk_date = fa.sk_slot_date
  WHERE
    date = DATE_TRUNC('DAY', DATE_ADD(CURRENT_TIMESTAMP(), -1))
)
SELECT
  aa.sk_user_agent,
  du.dados_agente_id AS sk_agent,
  aa.agent_status,
  aa.week_accreditation,
  aa.activation,
  aa.week_activation,
  DATE_ADD(aa.week_activation, 28) AS week_activation_frame,
  DATEDIFF(DAY, week_activation, CURRENT_DATE) AS days_since_activation_week,
  aa.agent_actual_type,
  aa.last_disqualification,
  aa.last_disqualification_return,
  aa.disqualification_reason,
  aa.permanently_disqualified,
  aa.last_suspension,
  aa.last_suspension_return,
  aa.suspension_reason,
  c.contractname,
  DATE(c.timestamp) AS dt_contract,
  ar.ult_area_associada,
  ar.dt_ult_area_associada
FROM dw_public.dim_user AS du
LEFT JOIN aux_agents_prep AS aa
  ON du.id = aa.sk_user_agent
LEFT JOIN contract AS c
  ON c.id = du.id
LEFT JOIN last_agent_area AS ar
  ON ar.sk_agent = du.dados_agente_id
WHERE
  c.r = 1