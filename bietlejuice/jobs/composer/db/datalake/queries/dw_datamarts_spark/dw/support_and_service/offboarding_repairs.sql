WITH jira_fields AS (
  SELECT
    CAST(
      COALESCE(
        REGEXP_EXTRACT(SPLIT(GET_JSON_OBJECT(fields, '$.summary'),'ontrato')[1], '(\\d+)'),
        REGEXP_EXTRACT(GET_JSON_OBJECT(fields, '$.summary'),' *<(\\d+)>')
      ) AS BIGINT
    ) AS sk_contract,
    key,
    GET_JSON_OBJECT(fields, '$.priority.name') AS priority,
    GET_JSON_OBJECT(fields, '$.status.name') AS status,
    GET_JSON_OBJECT(fields, '$.resolution.name') AS resolution,
    GET_JSON_OBJECT(fields, '$.customfield_11537.value') AS company,
    CASE 
      WHEN GET_JSON_OBJECT(fields, '$.customfield_11536') = 'null' THEN NULL
      ELSE CAST(GET_JSON_OBJECT(fields, '$.customfield_11536') AS DECIMAL) 
    END AS total_repair_value,
    CASE 
      WHEN LENGTH(GET_JSON_OBJECT(fields, '$.customfield_11684')) > 9 THEN DATE(DATE_FORMAT(SUBSTRING(GET_JSON_OBJECT(fields, '$.customfield_11684'),1,10),'y-M-d'))
      ELSE NULL 
    END AS dt_repair_booked,
    CASE 
      WHEN LENGTH(GET_JSON_OBJECT(fields, '$.customfield_11538')) > 9 THEN DATE(DATE_FORMAT(SUBSTRING(GET_JSON_OBJECT(fields, '$.customfield_11538'),1,10),'y-M-d'))
      ELSE NULL 
    END AS dt_partner_approved,
    CASE 
      WHEN LENGTH(GET_JSON_OBJECT(fields, '$.customfield_11535')) > 9 THEN DATE(DATE_FORMAT(SUBSTRING(GET_JSON_OBJECT(fields, '$.customfield_11535') ,1,10),'y-M-d'))
      ELSE NULL 
    END AS dt_repair_completed,
    CASE 
      WHEN LENGTH(GET_JSON_OBJECT(fields, '$.customfield_11698')) > 9 THEN DATE(DATE_FORMAT(SUBSTRING(GET_JSON_OBJECT(fields, '$.customfield_11698'),1,10),'y-M-d'))
      ELSE NULL 
    END AS dt_budget_done,
    CAST(DATE_FORMAT(SUBSTRING(GET_JSON_OBJECT(fields, '$.created') ,1,19), 'y-M-d H:m:s') AS TIMESTAMP) AS ts_created,
    CAST(DATE_FORMAT(SUBSTRING(GET_JSON_OBJECT(fields, '$.updated'), 1, 19), 'y-M-d H:m:s') AS TIMESTAMP) AS ts_updated,
    CASE 
      WHEN LENGTH(GET_JSON_OBJECT(fields, '$.resolutiondate')) > 9 THEN CAST(DATE_FORMAT(SUBSTRING(GET_JSON_OBJECT(fields, '$.resolutiondate'),1,19), 'y-M-d H:m:s') AS TIMESTAMP)
      ELSE NULL 
    END AS ts_resolution,
    LAST_VALUE(CAST(DATE_FORMAT(SUBSTRING(GET_JSON_OBJECT(fields, '$.updated'), 1, 19), 'y-M-d H:m:s') AS TIMESTAMP)) OVER (
      PARTITION BY key 
      ORDER BY CAST(DATE_FORMAT(SUBSTRING(GET_JSON_OBJECT(fields, '$.updated'), 1, 19), 'y-M-d H:m:s') AS TIMESTAMP) 
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS ts_last_update
  FROM 
    datalake_jira_clean.issues
  WHERE 
    key LIKE 'EDRB%'
),
repair_table AS (
  SELECT
    key,
    sk_contract,
    priority,
    status,
    resolution,
    ts_created,
    ts_resolution,
    ts_updated,
    company,
    dt_partner_approved,
    dt_repair_completed,
    dt_repair_booked,
    dt_budget_done,
    total_repair_value,
    CASE 
      WHEN ts_resolution IS NULL THEN NULL
      ELSE DATEDIFF(DATE_TRUNC('day',ts_resolution), DATE_TRUNC('day',ts_created)) 
    END AS days_created_to_solved,
    CASE 
      WHEN dt_partner_approved IS NULL THEN NULL
      ELSE DATEDIFF(dt_partner_approved, DATE_TRUNC('day', ts_created)) 
    END AS days_created_to_approved,
    CASE 
      WHEN dt_repair_completed IS NULL THEN NULL
      ELSE DATEDIFF(dt_repair_completed, DATE_TRUNC('day', ts_created)) 
    END AS days_created_to_completed,
    CASE 
      WHEN ts_resolution IS NULL OR dt_partner_approved IS NULL THEN NULL
      ELSE DATEDIFF(DATE_TRUNC('day',ts_resolution), dt_partner_approved) 
    END AS days_approved_to_solved,
    CASE 
      WHEN dt_repair_completed IS NULL OR dt_partner_approved IS NULL THEN NULL 
      ELSE DATEDIFF(dt_repair_completed, dt_partner_approved) 
    END AS days_approved_to_completed
  FROM
    jira_fields
  WHERE 
    ts_updated = ts_last_update
),
repair_leadtimes AS (
  SELECT 
    *, 
    CASE
      WHEN days_created_to_completed IS NULL THEN NULL
      WHEN days_created_to_completed BETWEEN 0 AND 15 THEN TRUE
      ELSE FALSE
    END AS is_sla_total_repair_achieved,
    CASE
      WHEN days_created_to_approved IS NULL THEN NULL
      WHEN dt_partner_approved < '2021-11-15' AND days_created_to_approved BETWEEN 0 AND 5 THEN TRUE
      WHEN dt_partner_approved >= '2021-11-15' AND days_created_to_approved BETWEEN 0 AND 3 THEN TRUE
      ELSE FALSE
    END AS is_sla_approval_achieved,
    CASE
      WHEN days_approved_to_completed IS NULL THEN NULL
      WHEN dt_repair_completed < '2021-10-01' AND days_approved_to_completed BETWEEN 0 AND 10 THEN TRUE
      WHEN dt_repair_completed >= '2021-10-01' AND days_approved_to_completed BETWEEN 0 AND 7 THEN TRUE
      ELSE FALSE
    END AS is_sla_execution_achieved
  FROM
    repair_table
)
SELECT 
  rl.sk_contract,
  dr.city_id AS sk_city,
  key,
  priority,
  status,
  resolution,
  company,
  total_repair_value,
  days_created_to_solved,
  days_created_to_approved,
  days_created_to_completed,
  days_approved_to_solved,
  days_approved_to_completed,
  is_sla_total_repair_achieved,
  is_sla_approval_achieved,
  is_sla_execution_achieved,
  NULLIF(dr.city_group,'') AS city_group,
  NULLIF(dr.city_name,'') AS city_name,
  NULLIF(dr.name,'') AS name,
  NULLIF(dr.regional,'') AS regional,
  NULLIF(dr.regional_inspection,'') AS regional_inspection,
  NULLIF(dr.region_code,'') AS region_code,
  NULLIF(dr.region_code_inspector,'') AS region_code_inspector,
  dr.tier AS tier,
  dt_partner_approved,
  dt_repair_completed,
  dt_repair_booked,
  dt_budget_done,
  ts_created,
  ts_resolution,
  ts_updated
FROM 
  repair_leadtimes rl
LEFT JOIN
  dw_public.fact_house_listings fhl 
    ON fhl.sk_contract = rl.sk_contract
LEFT JOIN 
  dw_public.dim_region dr 
    ON fhl.sk_region = dr.sk_region