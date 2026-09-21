WITH last_updated_assessment AS (
  SELECT DISTINCT
    da.sk_assessment,
    MAX(da.ts_updated) AS ts_updated
  FROM
    dw_inspections.dim_assessment AS da
  GROUP BY 1
),

assesment AS (
  SELECT DISTINCT
    fi.sk_inspection,
    lua.sk_assessment,
    da.ts_created,
    da.dt_owner_limit_revision,
    da.dt_tenant_limit_revision,
    da.ts_updated
  FROM
    last_updated_assessment AS lua
  JOIN
    dw_inspections.dim_assessment AS da
    ON lua.sk_assessment = da.sk_assessment AND lua.ts_updated = da.ts_updated
  JOIN
    dw_inspections.fact_inspection AS fi
    ON fi.sk_assessment = da.sk_assessment
),

rent_flows AS (
  SELECT DISTINCT
    sk_contract,
    sk_region
  FROM dw_rent.fact_listing_rent_flows
  WHERE sk_contract != -1
),

base AS (
  SELECT DISTINCT
    i.id_inspection,
    i.id_contract,
    i.status,
    i.id_inspector,
    CAST(a.TS_CREATED as date) dt_inspection,
    i.ts_updated,
    a.dt_owner_limit_revision sent_to_owner_review_limit_dt,
    a.dt_tenant_limit_revision review_started_by_tenant_limit_dt,
    CASE
      WHEN regexp_extract(i.id_contract, '\b\d+[1-3]\b', 0) IS NOT NULL THEN 1
      WHEN (regexp_extract(i.id_contract, '\b\d+[0]\b', 0) IS NOT NULL AND i.ts_updated >= CAST('2023-08-15' as timestamp) AND i.status = 'sent_to_tenant_review') THEN 1
      ELSE 0
    END as test,
    CASE WHEN dc.rent >= 2500 THEN 'high_value' ELSE NULL END as high_value_tag,
    region_code_inspector
  FROM
    datalake_inspection_services_clean.inspection_aud i
  JOIN
    assesment AS a
    ON a.sk_inspection = i.id_inspection
  LEFT JOIN
    dw_rent.dim_contract AS dc
    ON dc.sk_contract = i.id_contract
  LEFT JOIN
    rent_flows AS rf
    ON rf.sk_contract = dc.sk_contract
  LEFT JOIN
    dw_public.dim_region AS dr
    ON dr.sk_region = rf.sk_region
  WHERE
    1 = 1
    AND i.type = 'offboarding'
    AND a.TS_CREATED >= CAST('2025-01-01' as date)
    AND i.status NOT IN('cancelled', 'scheduled')
),

tenant_rev AS (
  SELECT
    id_inspection,
    id_contract,
    test
  FROM
    base
  WHERE
    1 = 1
    AND test = 1
    AND status IN('sent_to_tenant_review', 'review_started_by_tenant')
),

base_events AS (
  SELECT DISTINCT
    b.id_inspection,
    b.id_contract,
    b.dt_inspection,
    tr.test AS tenant_review,
    b.status,
    CASE WHEN b.status = 'received' THEN b.ts_updated ELSE NULL END as received_dt,
    CASE WHEN b.status = 'processing' THEN b.ts_updated ELSE NULL END as processing_dt,
    CASE WHEN b.status IN ('sent_to_analysis', 'sent_to_repair_analysis') THEN b.ts_updated ELSE NULL END as sent_to_repair_analysis_dt,
    CASE WHEN b.status = 'sent_to_owner_review' THEN b.ts_updated ELSE NULL END as sent_to_owner_review_dt,
    CASE WHEN b.status = 'sent_to_owner_review' THEN sent_to_owner_review_limit_dt ELSE NULL END as sent_to_owner_review_limit_dt,
    CASE WHEN b.status = 'review_started_by_owner' THEN b.ts_updated ELSE NULL END as review_started_by_owner,
    CASE WHEN b.status = 'sent_to_tenant_review' THEN b.ts_updated ELSE NULL END as sent_to_tenant_review_dt,
    CASE WHEN b.status = 'sent_to_tenant_review' THEN review_started_by_tenant_limit_dt ELSE NULL END as review_started_by_tenant_limit_dt,
    CASE WHEN b.status = 'review_started_by_tenant' THEN b.ts_updated ELSE NULL END as review_started_by_tenant_dt,
    CASE WHEN b.status = 'sent_to_contestation_analysis' THEN b.ts_updated ELSE NULL END as sent_to_contestation_analysis_dt,
    CASE WHEN b.status = 'contestation_analysis_finished' THEN b.ts_updated ELSE NULL END as contestation_an_dt,
    CASE WHEN b.status = 'reviewed' THEN b.ts_updated ELSE NULL END as reviewed_dt,
    b.ts_updated,
    b.high_value_tag,
    b.region_code_inspector,
    b.id_inspector
  FROM
    base AS b
  LEFT JOIN
    tenant_rev tr
    ON b.id_inspection = tr.id_inspection
  WHERE
    b.dt_inspection >= CAST('2025-01-01' as date)
),
funnel AS (
  SELECT
    id_inspection,
    id_contract,
    dt_inspection,
    tenant_review,
    high_value_tag,
    region_code_inspector,
    id_inspector,
    MAX(received_dt) received_dt,
    MAX(processing_dt) processing_dt,
    MAX(sent_to_repair_analysis_dt) sent_to_repair_analysis_dt,
    MAX(sent_to_owner_review_dt) sent_to_owner_review_dt,
    MAX(sent_to_owner_review_limit_dt) sent_to_owner_review_limit_dt,
    MAX(review_started_by_owner) review_started_by_owner,
    MAX(sent_to_tenant_review_dt) sent_to_tenant_review_dt,
    MAX(review_started_by_tenant_limit_dt) review_started_by_tenant_limit_dt,
    MAX(review_started_by_tenant_dt) review_started_by_tenant_dt,
    MAX(sent_to_contestation_analysis_dt) sent_to_contestation_analysis_dt,
    MAX(reviewed_dt) reviewed_dt,
    MAX(ts_updated) ts_updated
  FROM
    base_events  -- CORREÇÃO: Agora lê de base_events, pois base não tem received_dt
  GROUP BY
    id_inspection, id_contract, dt_inspection, tenant_review, high_value_tag, region_code_inspector, id_inspector
),

base3 AS (
  SELECT
    i.id_inspection,
    i.id_contract,
    i.dt_inspection,
    i.tenant_review,
    received_dt,
    processing_dt,
    sent_to_repair_analysis_dt,
    sent_to_owner_review_dt,
    IF(sent_to_owner_review_limit_dt > DATE(sent_to_owner_review_dt) + INTERVAL 5 day, DATE(sent_to_owner_review_dt) + INTERVAL 5 day, sent_to_owner_review_limit_dt) AS sent_to_owner_review_limit_dt,
    review_started_by_owner,
    sent_to_tenant_review_dt,
    IF(review_started_by_tenant_limit_dt > DATE(sent_to_tenant_review_dt) + INTERVAL 5 day, DATE(sent_to_tenant_review_dt) + INTERVAL 5 day, review_started_by_tenant_limit_dt) AS review_started_by_tenant_limit_dt,
    review_started_by_tenant_dt,
    sent_to_contestation_analysis_dt,
    reviewed_dt,
    i.ts_updated,
    rr.id_repair_request,
    c.id_contestation,
    CASE
      WHEN rr.is_from_analysis IS NOT NULL THEN 1
      WHEN rr.is_from_analysis = TRUE THEN 1
      ELSE 0
    END AS repair_from_analysis,
    CASE
      WHEN rr.is_exempted IS NULL THEN 0
      WHEN rr.is_exempted = FALSE THEN 0
      ELSE 1
    END AS repair_exempted,
    CASE WHEN createdBy.reviewer_type = 'ADMIN' THEN 1 ELSE 0 END repair_created_by_an1,
    CASE WHEN createdBy.reviewer_type = 'OWNER' THEN 1 ELSE 0 END repair_created_by_owner,
    CASE WHEN createdBy.reviewer_type = 'TENANT' THEN 1 ELSE 0 END repair_created_by_tenant,
    CASE WHEN grantedBy.reviewer_type = 'ADMIN' THEN 1 ELSE 0 END repair_granted_by_an1,
    CASE WHEN grantedBy.reviewer_type = 'TENANT' THEN 1 ELSE 0 END repair_granted_by_tenant,
    CASE WHEN grantedBy.reviewer_type = 'OWNER' THEN 1 ELSE 0 END repair_granted_by_owner,
    high_value_tag,
    region_code_inspector,
    id_inspector
  FROM
    funnel AS i
  JOIN
    datalake_inspection_services_clean.assessment AS a
    ON a.id_inspection = i.id_inspection
  JOIN
    datalake_inspection_services_clean.room AS r
    ON r.id_assessment = a.id_assessment
  JOIN
    datalake_inspection_services_clean.item_group AS ig
    ON ig.id_room = r.id_room
  LEFT JOIN
    datalake_inspection_services_clean.repair_request AS rr
    ON rr.id_item_group = ig.id_item_group
  LEFT JOIN
    datalake_inspection_services_clean.contestation AS c
    ON c.ID_REPAIR_REQUEST = rr.ID_REPAIR_REQUEST
  LEFT JOIN
    datalake_inspection_services_clean.reviewer AS createdBy
    ON createdBy.id_reviewer = rr.id_reviewer
  LEFT JOIN
    datalake_inspection_services_clean.reviewer AS grantedBy
    ON grantedBy.id_reviewer = rr.id_granted_by
),

repairs AS (
  SELECT id_inspection, COUNT(DISTINCT id_repair_request) repairs
  FROM base3 GROUP BY 1
),

an1_reps AS (
  SELECT id_inspection, COUNT(DISTINCT id_repair_request) repair_from_analysis
  FROM base3 WHERE repair_from_analysis = 1 GROUP BY 1
),

owner_reps AS (
  SELECT id_inspection, COUNT(DISTINCT id_repair_request) repair_created_by_owner
  FROM base3 WHERE repair_created_by_owner = 1 GROUP BY 1
),

repair_exempted AS (
  SELECT id_inspection, COUNT(DISTINCT id_repair_request) repair_exempted
  FROM base3 WHERE repair_exempted = 1 GROUP BY 1
),

repair_contested AS (
  SELECT id_inspection, COUNT(DISTINCT id_contestation) repair_contested
  FROM base3 GROUP BY 1
),

IS_events AS (
  SELECT DISTINCT
    i.id_inspection,
    i.id_contract,
    i.dt_inspection,
    IF(i.tenant_review IS NULL, 0, i.tenant_review) tenant_review,
    i.received_dt,
    i.processing_dt,
    i.sent_to_repair_analysis_dt,
    i.sent_to_owner_review_dt,
    i.sent_to_owner_review_limit_dt,
    i.review_started_by_owner,
    i.sent_to_tenant_review_dt,
    i.review_started_by_tenant_limit_dt,
    i.review_started_by_tenant_dt,
    i.sent_to_contestation_analysis_dt,
    i.reviewed_dt,
    r.repairs,
    IF(ar.repair_from_analysis IS NULL, 0, ar.repair_from_analysis) repair_from_analysis,
    IF(owr.repair_created_by_owner IS NULL, 0, owr.repair_created_by_owner) repair_created_by_owner,
    IF(rc.repair_contested IS NULL, 0, rc.repair_contested) repair_contested,
    IF(re.repair_exempted IS NULL, 0, re.repair_exempted) repair_exempted,
    high_value_tag,
    region_code_inspector,
    id_inspector
  FROM
    base3 i
  LEFT JOIN repairs r ON r.id_inspection = i.id_inspection
  LEFT JOIN an1_reps ar ON ar.id_inspection = i.id_inspection
  LEFT JOIN owner_reps owr ON owr.id_inspection = i.id_inspection
  LEFT JOIN repair_exempted re ON re.id_inspection = i.id_inspection
  LEFT JOIN repair_contested rc ON rc.id_inspection = i.id_inspection
),

base_cases AS (
    SELECT
        cp.case_number,
        cp.ts_started,
        cp.ts_solved,
        cp.ts_closed,
        cp.sk_contract,
        cp.last_agent_email as email,
        CASE
            WHEN cp.last_team IN ('KIRK', 'SPOC - HV', 'SPOC - LV', 'Core - LV', 'Core - HV') THEN 'Análise de Reparos'
            WHEN cp.last_team = 'AC' THEN 'Análise de Contestação'
            ELSE cp.last_team
        END AS last_team,
        CASE
            WHEN cp.last_department IN ('[AeC] CX Ongoing [FRONT] [POS]', '[AeC] CX Reparos [FRONT] [POS]', 'CX Ongoing [FRONT] [POS]') THEN 'CX Reparos [FRONT] [POS]'
            ELSE cp.last_department
        END AS last_department,
        cp.platform,
        cp.is_spoc_test,
        ROW_NUMBER() OVER(PARTITION BY cp.case_number ORDER BY cp.ts_load DESC) as rn
    FROM dw_bpo_performance.cases_perspective AS cp
    WHERE to_date(cp.ts_started) >= current_date() - INTERVAL 12 MONTH
),


an1_events AS (
  SELECT
    ft.sk_contract,
    ft.sk_ticket,
    du.email,
    DATE(dt.ts_created_brt) as created_date,
    DATE(ft.ts_solved) as solved_date,
    ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY DATE(ft.ts_solved) ASC) AS rk
  FROM
    dw_customer_support.fact_tickets AS ft
  LEFT JOIN
    dw_customer_support.dim_ticket AS dt
    ON ft.sk_ticket = dt.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_zendesk_user AS du
    ON ft.sk_zendesk_assignee_user = du.sk_zendesk_user
  WHERE
    dt.group_name in ('Análise de reparos [OFF] [POS] [BACK] ')
    AND dt.status not in ('deleted')
    AND dt.tags not like '%closed_by_merge%'
    AND dt.tags not like '%fechamento_em_massa_19102023%'
    AND ft.sk_ticket not in ('67559749','67559785','67559036','67315629','67632524','67578670','67613882','67562139','67577586','67619607','67558654','67549115','67558995','67562220','67558702','67580136','67550673','67549581','67551316','67547746','67550817','67548006','67559280','67549806','67558037','67558304','67632030','67318645','67619528','67549211','67318289','67557940','67551383','67558242')

  UNION ALL

SELECT CAST(c.sk_contract AS INTEGER) as id_contract,
c.case_number,
c.email,
date(c.ts_started) as created_date,
date(c.ts_closed) as solved_date,
ROW_NUMBER() OVER (PARTITION BY c.sk_contract ORDER BY date(c.ts_closed) ASC) AS rk
--1 AS rk -- 'Não se aplica'
FROM base_cases AS c
WHERE c.ts_started >= DATE('2026-04-23')
    AND c.email IS NOT NULL
    AND c.last_team IN ('Análise de Reparos')
),

amplitude_events AS (
  SELECT
    CAST(sa.id_inspection AS STRING) AS id_inspection,
    sa.id_contract,
    CASE WHEN sa.has_owner_access_review  THEN 1 END AS pp_open,
    sa.ts_first_owner_access_review                  AS pp_open_dt,
    CASE WHEN sa.has_tenant_access_review THEN 1 END AS iq_open,
    sa.ts_first_tenant_access_review                 AS iq_open_dt
  FROM datalake_amplitude_inspections.inspection_stages_access AS sa
  WHERE sa.inspection_type = 'offboarding'
    AND (
      sa.ts_first_owner_access_review  IS NOT NULL
      OR sa.ts_first_tenant_access_review IS NOT NULL
    )
),

inspections_cycle AS (
  SELECT DISTINCT
    i.id_inspection,
    i.id_contract,
    i.dt_inspection,
    i.tenant_review,
    ae.email,
    i.received_dt,
    i.processing_dt,
    i.sent_to_repair_analysis_dt,
    i.sent_to_owner_review_dt,
    i.sent_to_owner_review_limit_dt,
    aem.pp_open,
    aem.pp_open_dt,
    i.review_started_by_owner,
    i.sent_to_tenant_review_dt,
    i.review_started_by_tenant_limit_dt,
    aem.iq_open,
    aem.iq_open_dt,
    i.review_started_by_tenant_dt,
    i.sent_to_contestation_analysis_dt,
    i.reviewed_dt,
    i.repairs,
    i.repair_from_analysis,
    i.repair_created_by_owner,
    i.repair_contested,
    i.repair_exempted,
    i.high_value_tag,
    i.region_code_inspector,
    i.id_inspector
  FROM
    IS_events i
  LEFT JOIN
    an1_events ae
    ON ae.sk_contract = i.id_contract AND ae.rk = 1
  LEFT JOIN
    amplitude_events aem
    ON aem.id_inspection = i.id_inspection
),

db AS (
  SELECT
    id_inspection,
    id_contract,
    high_value_tag,
    dt_inspection,
    tenant_review,
    email,
    DATE(received_dt) as received_dt,
    DATE(processing_dt) as processing_dt,
    DATE(sent_to_repair_analysis_dt) as sent_to_repair_analysis_dt,
    DATE(sent_to_owner_review_dt) as sent_to_owner_review_dt,
    DATE(sent_to_owner_review_limit_dt) as sent_to_owner_review_limit_dt,
    IF(DATE(pp_open_dt) > DATE(sent_to_owner_review_limit_dt), NULL, pp_open) AS pp_open,
    DATE(pp_open_dt) as pp_open_dt,
    DATE(review_started_by_owner) as review_started_by_owner,
    DATE(sent_to_tenant_review_dt) as sent_to_tenant_review_dt,
    DATE(review_started_by_tenant_limit_dt) as review_started_by_tenant_limit_dt,
    IF(DATE(iq_open_dt) > DATE(review_started_by_tenant_limit_dt), NULL, iq_open) AS iq_open,
    DATE(iq_open_dt) as iq_open_dt,
    DATE(review_started_by_tenant_dt) as review_started_by_tenant_dt,
    DATE(sent_to_contestation_analysis_dt) as sent_to_contestation_analysis_dt,
    DATE(reviewed_dt) as reviewed_dt,
    repairs,
    repair_from_analysis,
    repair_created_by_owner,
    repair_contested,
    repair_exempted,
    region_code_inspector,
    id_inspector
  FROM
    inspections_cycle
),
contracts_kirk AS (
        SELECT DISTINCT fi.sk_contract
        FROM dw_inspections.fact_inspection fi
        LEFT JOIN dw_inspections.dim_inspection di ON fi.sk_inspection = di.sk_inspection
        WHERE di.ai_repair_analysis_control_group = 'false'
            AND di.ai_repair_analysis_wave_name IS NOT NULL
            AND fi.country_code = 'BR'
            AND fi.ts_synced IS NOT NULL
            AND di.inspection_type = 'offboarding'
    )

SELECT
  id_contract,
  high_value_tag,
  id_inspection,
  email,
  IF(
    sent_to_owner_review_limit_dt > pp_open_dt
    OR sent_to_owner_review_limit_dt IS NULL,
    pp_open_dt,
    sent_to_owner_review_limit_dt
  ) AS pp_open_dt,
  pp_open,
  tenant_review,
  IF(
    review_started_by_tenant_limit_dt > iq_open_dt
    OR review_started_by_tenant_limit_dt IS NULL,
    iq_open_dt,
    review_started_by_tenant_limit_dt
  ) AS iq_open_dt,
  iq_open,
  IF(
    sent_to_tenant_review_dt IS NULL,
    reviewed_dt,
    sent_to_tenant_review_dt
  ) AS reviwed_date_pp,
  repair_created_by_owner,
  IF(repair_contested >= 1, 1, 0) as contest_iq,
  IF(
    sent_to_contestation_analysis_dt IS NULL,
    reviewed_dt,
    sent_to_contestation_analysis_dt
  ) AS reviwed_date_iq,
  sent_to_owner_review_dt,
  id_inspector,
  region_code_inspector,
  reviewed_dt as review_dt_final,
  CASE WHEN ck.sk_contract IS NOT NULL THEN 1 ELSE 0 END as is_kirk
  FROM
  db
LEFT JOIN contracts_kirk ck on ck.sk_contract = db.id_contract
ORDER BY
  5 DESC
