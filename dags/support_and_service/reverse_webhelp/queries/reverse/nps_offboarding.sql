WITH
inspections AS (
    SELECT
        fi.sk_contract,
        fi.ts_synced,
        fi.sk_inspection,
        di.inspection_type
    FROM dw_inspections.fact_inspection fi
    LEFT JOIN dw_inspections.dim_inspection di
        ON fi.sk_inspection = di.sk_inspection
    WHERE 
        di.inspection_type IN ('offboarding', 'verification')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY fi.sk_contract, fi.ts_synced ORDER BY fi.ts_synced ASC) = 1
), 
terminator AS (
    SELECT
        MAX(t.id_termination) id_request,
        t.id_contract,
        MAX(DATE(t.ts_termination_request)) termination_request,
        MAX(DATE(t.dt_termination)) termination_date,
        CASE WHEN MIN(DATE(ins.ts_synced)) > MIN(DATE(t.ts_termination_request)) THEN MIN(DATE(ins.ts_synced))
            ELSE NULL
        END inspection_date,
        ins.inspection_type,
        t.status inspection_status,
        MAX(DATE(dc.ts_analyst_annulment_input)) ended_confirmed,
        dc.status contract_status,
        MAX(DATE(ct.ts_termination_finished)) termination_finished,
        dc.is_exit_inspection_opted_out,
        ct.is_repair_tenant_duty,
        ct.repair_resolution,
        ct.reason,
        ct.category,
        ct.is_before_contract_start,
        ct.id_house,
        fhl.sk_owner,
        tc.is_pro_owner,
        dr.short_region_name reg_state,
        dr.city_id,
        dc.rent
    FROM datalake_terminator.termination t
    LEFT JOIN datalake_offboarding.contract_termination ct
        ON t.id_termination = ct.id_termination
    LEFT JOIN dw_rent.dim_contract dc
        ON t.id_contract = dc.sk_contract
    LEFT JOIN inspections ins
        ON t.id_contract = ins.sk_contract
    LEFT JOIN dw_rent.dim_house_listing dhl
        ON ct.id_house = dhl.id_house 
        AND dhl.is_last_version
    LEFT JOIN dw_rent.fact_house_listings fhl
        ON dhl.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN datalake_terminator_clean.termination_characteristics tc
        ON t.id_termination = tc.id_termination
    LEFT JOIN dw_public.dim_region dr
        ON fhl.sk_region = dr.sk_region
    WHERE 
    t.status NOT IN ('CANCELED')
    AND dc.country_code = 'BR'
    AND t.ts_termination_request BETWEEN DATE('{load_start_date}') - INTERVAL '24' MONTH AND DATE('{load_start_date}')
    GROUP BY 2, 6, 7, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22
),

new_mediation AS (
    SELECT
        t.id_contract sk_contract,
        t.id_zendesk_task sk_ticket,
        (t.ts_termination_request - INTERVAL '1' HOUR) as created_date
    FROM datalake_terminator.termination t
    LEFT JOIN dw_customer_support.dim_ticket dt
        ON t.id_zendesk_task = dt.sk_ticket
    WHERE t.task_type = 'TERMINATION_LANDLORD'
    AND t.ts_termination_request>= DATE('2023-01-01')
    AND dt.group_name like '%[POS] [BACK]'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY t.id_contract ORDER BY t.ts_termination_request DESC) = 1
),
offboarding AS (
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
    FROM 
        terminator 
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY inspection_date ASC, termination_request DESC) = 1
),
-- WITH REPAIRS
repair_resolution_terminations AS (
    SELECT
        ft.sk_contract,
        ft.sk_termination_date,
        ft.total_tentant_repair_ar,
        ft.repairs_added_by_owner_review,
        ft.repairs_exempted_by_owner_review,
        ft.total_tentant_repair_review,
        ft.repairs_exempted_ac,
        ft.repairs_absorbed_ac,
        ft.total_tentant_repair_ac
    FROM 
        dw_offboarding.fact_terminations ft
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY ft.ts_termination_request DESC) = 1
),
-- SPOC CONTRACTS
spoc_contracts AS (
    SELECT
        ft.sk_termination,
        ft.sk_contract,
        DATE(ft.ts_termination_request) ts_termination_request,
        ft.is_spoc_contract,
        ft.spoc_wave,
        ft.is_spoc_control_group,
        dt.team,
        da.email agent_email
    FROM 
        dw_offboarding.fact_terminations ft
    LEFT JOIN dw_offboarding.dim_termination dt
        ON ft.sk_termination = dt.sk_termination
    LEFT JOIN dw_customer_support.dim_analyst da
        ON ft.sk_analyst = da.sk_analyst
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY ft.ts_termination_request DESC) = 1
)
-- MAIN QUERY
SELECT DISTINCT
  ans.sk_nps_answer,
  DATE(ans.ts_answered) ts_answered,
  camp.name,
  camp.metric_group,
  disp.sk_contract,
  ofb.termination_request tr_dt,
  ofb.termination_date td_dt,
  ofb.termination_finished tf_dt,
  disp.score,
  ans.score_category,
  camp.customer_type,
  ofb.is_exit_inspection_opted_out opted_out,
  IF(rrt.repairs_absorbed_ac > 0 OR total_tentant_repair_ac > 0, TRUE, FALSE) with_AC_repairs,
  ofb.reg_state,
  ofb.rent,
  IF(ofb.rent >= 2500, 'High Value', 'Non High Value') high_value,
  disp.sk_user,
  spc.spoc_wave,
  CASE WHEN ofb.termination_request < DATE('2025-05-22') AND spc.is_spoc_contract = TRUE THEN 'before_wave_6'
    WHEN ofb.termination_request >= DATE('2025-05-22') AND spc.is_spoc_contract = TRUE AND (spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL) AND (spc.team = 'ROLLOUT' OR spc.team IS NULL) THEN 'rollout'
    WHEN ofb.termination_request >= DATE('2025-05-22') AND spc.is_spoc_contract = TRUE AND (spc.is_spoc_control_group = FALSE OR spc.is_spoc_control_group IS NULL) AND spc.team = 'LAB' THEN 'lab_test'
    WHEN ofb.termination_request >= DATE('2025-05-22') AND spc.is_spoc_contract = TRUE AND spc.is_spoc_control_group = TRUE THEN 'lab_control'
    ELSE NULL
  END spoc_class,
  med.created_date med_created_dt,
  IF(spc.agent_email LIKE '%webhelp%', spc.agent_email, NULL) spoc_agent_email,
  ans.comment,
  YEAR(ans.ts_answered) AS year,
  MONTH(ans.ts_answered) AS month,
  DAY(ans.ts_answered) AS day,
  NOW() AS ts_load
FROM dw_customer_satisfaction.dim_nps_answer ans
LEFT JOIN dw_customer_satisfaction.fact_nps_dispatches disp
  ON ans.sk_nps_answer = disp.sk_nps_answer
INNER JOIN dw_customer_satisfaction.dim_nps_campaign camp
  ON disp.sk_nps_campaign = camp.sk_nps_campaign
LEFT JOIN offboarding ofb
  ON disp.sk_contract = ofb.id_contract
LEFT JOIN repair_resolution_terminations rrt
  ON disp.sk_contract = rrt.sk_contract
LEFT JOIN new_mediation med
  ON ofb.id_contract = med.sk_contract
LEFT JOIN spoc_contracts spc
  ON disp.sk_contract = spc.sk_contract
WHERE disp.sk_nps_answer > 0
AND camp.purpose = 'main'
AND camp.business_context = 'forRent'
AND camp.metric_group IN ('ppoffboarding', 'iqoffboarding')
AND ans.ts_answered >= DATE('{load_start_date}') - INTERVAL '12' MONTH 
AND ans.ts_answered >= DATE('2025-01-01')
AND (spc.is_spoc_contract = TRUE OR med.created_date IS NOT NULL)