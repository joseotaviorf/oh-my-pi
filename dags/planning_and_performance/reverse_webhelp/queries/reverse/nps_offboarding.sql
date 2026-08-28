WITH inspections AS (
  SELECT
    sk_contract,
    ts_synced,
    sk_inspection,
    inspection_type
  FROM (
    SELECT
      fi.sk_contract,
      fi.ts_synced,
      fi.sk_inspection,
      di.inspection_type,
      ROW_NUMBER() OVER (PARTITION BY fi.sk_contract, fi.ts_synced ORDER BY fi.ts_synced ASC) AS _w
    FROM dw_inspections.fact_inspection AS fi
    LEFT JOIN dw_inspections.dim_inspection AS di
      ON fi.sk_inspection = di.sk_inspection
    WHERE
      di.inspection_type IN ('offboarding', 'verification')
  ) AS _t
  WHERE
    _w = 1
), terminator AS (
  SELECT
    MAX(t.id_termination) AS id_request,
    t.id_contract,
    MAX(CAST(t.ts_termination_request AS DATE)) AS termination_request,
    MAX(CAST(t.dt_termination AS DATE)) AS termination_date,
    CASE
      WHEN MIN(CAST(ins.ts_synced AS DATE)) > MIN(CAST(t.ts_termination_request AS DATE))
      THEN MIN(CAST(ins.ts_synced AS DATE))
      ELSE NULL
    END AS inspection_date,
    ins.inspection_type,
    t.status AS inspection_status,
    MAX(CAST(dc.ts_analyst_annulment_input AS DATE)) AS ended_confirmed,
    dc.status AS contract_status,
    MAX(CAST(ct.ts_termination_finished AS DATE)) AS termination_finished,
    dc.is_exit_inspection_opted_out,
    ct.is_repair_tenant_duty,
    ct.repair_resolution,
    ct.reason,
    ct.category,
    ct.is_before_contract_start,
    ct.id_house,
    fhl.sk_owner,
    tc.is_pro_owner,
    dr.short_region_name AS reg_state,
    dr.city_id,
    dc.rent
  FROM datalake_terminator.termination AS t
  LEFT JOIN datalake_offboarding.contract_termination AS ct
    ON t.id_termination = ct.id_termination
  LEFT JOIN dw_rent.dim_contract AS dc
    ON t.id_contract = dc.sk_contract
  LEFT JOIN inspections AS ins
    ON t.id_contract = ins.sk_contract
  LEFT JOIN dw_rent.dim_house_listing AS dhl
    ON ct.id_house = dhl.id_house AND dhl.is_last_version
  LEFT JOIN dw_rent.fact_house_listings AS fhl
    ON dhl.sk_house_listing = fhl.sk_house_listing
  LEFT JOIN datalake_terminator_clean.termination_characteristics AS tc
    ON t.id_termination = tc.id_termination
  LEFT JOIN dw_public.dim_region AS dr
    ON fhl.sk_region = dr.sk_region
  WHERE
    NOT t.status IN ('CANCELED')
    AND dc.country_code = 'BR'
    AND t.ts_termination_request BETWEEN CAST('{load_start_date}' AS DATE) - INTERVAL '24' MONTH AND CAST('{load_start_date}' AS DATE)
  GROUP BY
    2,
    6,
    7,
    9,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22
), new_mediation AS (
  SELECT
    sk_contract,
    sk_ticket,
    created_date
  FROM (
    SELECT
      t.id_contract AS sk_contract,
      t.id_zendesk_task AS sk_ticket,
      (
        t.ts_termination_request - INTERVAL '1' HOUR
      ) AS created_date,
      ROW_NUMBER() OVER (PARTITION BY t.id_contract ORDER BY t.ts_termination_request DESC) AS _w,
      t.id_contract,
      t.ts_termination_request
    FROM datalake_terminator.termination AS t
    LEFT JOIN dw_customer_support.dim_ticket AS dt
      ON t.id_zendesk_task = dt.sk_ticket
    WHERE
      t.task_type = 'TERMINATION_LANDLORD'
      AND t.ts_termination_request >= CAST('2023-01-01' AS DATE)
      AND dt.group_name LIKE '%[POS] [BACK]'
  ) AS _t
  WHERE
    _w = 1
), offboarding AS (
  SELECT
    id_request,
    id_contract,
    termination_request,
    termination_date,
    inspection_date,
    inspection_type,
    inspection_status,
    ended_confirmed,
    contract_status,
    termination_finished,
    is_exit_inspection_opted_out,
    is_repair_tenant_duty,
    repair_resolution,
    reason,
    category,
    is_before_contract_start,
    id_house,
    sk_owner,
    is_pro_owner,
    reg_state,
    city_id,
    rent
  FROM (
    SELECT
      id_request,
      id_contract,
      termination_request,
      termination_date,
      inspection_date,
      inspection_type,
      inspection_status,
      ended_confirmed,
      contract_status,
      termination_finished,
      is_exit_inspection_opted_out,
      is_repair_tenant_duty,
      repair_resolution,
      reason,
      category,
      is_before_contract_start,
      id_house,
      sk_owner,
      is_pro_owner,
      reg_state,
      city_id,
      rent,
      ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY inspection_date ASC, termination_request DESC) AS _w
    FROM terminator
  ) AS _t
  WHERE
    _w = 1
), repair_resolution_terminations /* WITH REPAIRS */ AS (
  SELECT
    sk_contract,
    sk_termination_date,
    total_tentant_repair_ar,
    repairs_added_by_owner_review,
    repairs_exempted_by_owner_review,
    total_tentant_repair_review,
    repairs_exempted_ac,
    repairs_absorbed_ac,
    total_tentant_repair_ac
  FROM (
    SELECT
      ft.sk_contract,
      ft.sk_termination_date,
      ft.total_tentant_repair_ar,
      ft.repairs_added_by_owner_review,
      ft.repairs_exempted_by_owner_review,
      ft.total_tentant_repair_review,
      ft.repairs_exempted_ac,
      ft.repairs_absorbed_ac,
      ft.total_tentant_repair_ac,
      ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY ft.ts_termination_request DESC) AS _w,
      ft.ts_termination_request
    FROM dw_offboarding.fact_terminations AS ft
  ) AS _t
  WHERE
    _w = 1
), spoc_contracts /* SPOC CONTRACTS */ AS (
  SELECT
    sk_termination,
    sk_contract,
    ts_termination_request,
    is_spoc_contract,
    spoc_wave,
    is_spoc_control_group,
    team,
    agent_email
  FROM (
    SELECT
      ft.sk_termination,
      ft.sk_contract,
      CAST(ft.ts_termination_request AS DATE) AS ts_termination_request,
      ft.is_spoc_contract,
      ft.spoc_wave,
      ft.is_spoc_control_group,
      dt.team,
      da.email AS agent_email,
      ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY CAST(ft.ts_termination_request AS DATE) DESC) AS _w
    FROM dw_offboarding.fact_terminations AS ft
    LEFT JOIN dw_offboarding.dim_termination AS dt
      ON ft.sk_termination = dt.sk_termination
    LEFT JOIN dw_customer_support.dim_analyst AS da
      ON ft.sk_analyst = da.sk_analyst
  ) AS _t
  WHERE
    _w = 1
)
/* MAIN QUERY */
SELECT DISTINCT
  ans.sk_nps_answer,
  CAST(ans.ts_answered AS DATE) AS ts_answered,
  camp.name,
  camp.metric_group,
  disp.sk_contract,
  ofb.termination_request AS tr_dt,
  ofb.termination_date AS td_dt,
  ofb.termination_finished AS tf_dt,
  disp.score,
  ans.score_category,
  camp.customer_type,
  ofb.is_exit_inspection_opted_out AS opted_out,
  IF(rrt.repairs_absorbed_ac > 0 OR total_tentant_repair_ac > 0, TRUE, FALSE) AS with_AC_repairs,
  ofb.reg_state,
  ofb.rent,
  IF(ofb.rent >= 2500, 'High Value', 'Non High Value') AS high_value,
  disp.sk_user,
  spc.spoc_wave,
  CASE
    WHEN ofb.termination_request < CAST('2025-06-02' AS DATE)
    AND spc.is_spoc_contract = TRUE
    AND (
      spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL
    )
    THEN 'before_wave_6_lab_test'
    WHEN ofb.termination_request < CAST('2025-06-02' AS DATE)
    AND spc.is_spoc_contract = TRUE
    AND spc.is_spoc_control_group = TRUE
    THEN 'before_wave_6_lab_control'
    WHEN ofb.termination_request >= CAST('2025-05-22' AS DATE)
    AND spc.is_spoc_contract = TRUE
    AND (
      spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL
    )
    AND (
      spc.team = 'ROLLOUT' OR spc.team IS NULL
    )
    THEN 'rollout'
    WHEN ofb.termination_request BETWEEN CAST('2025-06-02' AS DATE) AND CAST('2025-07-29' AS DATE)
    AND spc.is_spoc_contract = TRUE
    AND (
      spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL
    )
    AND spc.team = 'LAB'
    THEN 'wave_6_lab_test'
    WHEN ofb.termination_request BETWEEN CAST('2025-07-30' AS DATE) AND CAST('{load_start_date}' AS DATE)
    AND spc.is_spoc_contract = TRUE
    AND (
      spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL
    )
    AND spc.team = 'LAB'
    THEN 'wave_6b_lab_test'
    WHEN ofb.termination_request BETWEEN CAST('2025-06-02' AS DATE) AND CAST('2025-07-29' AS DATE)
    AND spc.is_spoc_contract = TRUE
    AND spc.is_spoc_control_group = TRUE
    THEN 'wave_6_lab_control'
    WHEN ofb.termination_request BETWEEN CAST('2025-07-30' AS DATE) AND CAST('{load_start_date}' AS DATE)
    AND spc.is_spoc_contract = TRUE
    AND spc.is_spoc_control_group = TRUE
    THEN 'wave_6b_lab_control'
    ELSE NULL
  END AS spoc_class,
  med.created_date AS med_created_dt,
  med.sk_ticket AS med_sk_ticket,
  IF(spc.agent_email LIKE '%webhelp%', spc.agent_email, NULL) AS spoc_agent_email,
  ans.comment,
  YEAR(TO_DATE(CURRENT_DATE - 1)) AS year,
  MONTH(TO_DATE(CURRENT_DATE - 1)) AS month,
  DAY(TO_DATE(CURRENT_DATE - 1)) AS day,
  NOW() AS ts_load
FROM dw_customer_satisfaction.dim_nps_answer AS ans
LEFT JOIN dw_customer_satisfaction.fact_nps_dispatches AS disp
  ON ans.sk_nps_answer = disp.sk_nps_answer
INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS camp
  ON disp.sk_nps_campaign = camp.sk_nps_campaign
LEFT JOIN offboarding AS ofb
  ON disp.sk_contract = ofb.id_contract
LEFT JOIN repair_resolution_terminations AS rrt
  ON disp.sk_contract = rrt.sk_contract
LEFT JOIN new_mediation AS med
  ON ofb.id_contract = med.sk_contract
LEFT JOIN spoc_contracts AS spc
  ON disp.sk_contract = spc.sk_contract
WHERE
  disp.sk_nps_answer > 0
  AND camp.purpose = 'main'
  AND camp.business_context = 'forRent'
  AND camp.metric_group IN ('ppoffboarding', 'iqoffboarding')
  AND ans.ts_answered >= CAST('{load_start_date}' AS DATE) - INTERVAL '12' MONTH
  AND ans.ts_answered >= CAST('2025-01-01' AS DATE)
  AND (
    spc.is_spoc_contract = TRUE OR NOT med.created_date IS NULL
  )
