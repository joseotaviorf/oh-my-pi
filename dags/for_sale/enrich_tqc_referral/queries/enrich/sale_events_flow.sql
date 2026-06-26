WITH sale_visit_flows AS (
  SELECT
    v.id_visit,
    v.id_house,
    v.id_visitor AS id_buyer,
    uv.id_agent,
    v.id_agent AS id_user_sale_agent,
    CONCAT(v.id_visitor, '_', v.id_house) AS id_sale_flow,
    CASE
      WHEN v.visit_request_channel IN ('AGENT_PWA', 'AGENT_NATIVE') THEN 'Agent'
      WHEN v.visit_request_channel IN ('TENANT_PWA', 'TENANT_NATIVE') THEN 'Buyer'
      WHEN su.id_user_5a IS NOT NULL THEN 'Secretaria'
      WHEN u.email LIKE '%quintoandar.com.br' THEN 'Admin/CX'
      ELSE 'Other'
    END AS visit_creation_origin,
    visit_creation_origin AS first_visit_creation_origin,
    COALESCE(FROM_UTC_TIMESTAMP(v.ts_visit_rescheduled, COALESCE(ct.default_timezone, 'UTC')), FROM_UTC_TIMESTAMP(v.ts_created, COALESCE(ct.default_timezone, 'UTC'))) AS ts_visit_created,
    FROM_UTC_TIMESTAMP(v.ts_created, COALESCE(ct.default_timezone, 'UTC')) AS ts_first_visit_created,
    v.code AS visit_code,
    v.computed_status AS visit_status,
    COALESCE(ct.default_timezone, 'UTC') AS default_timezone,
    v.ts_visit AS ts_visit_scheduled_for,
    FROM_UTC_TIMESTAMP(v.ts_visit, COALESCE(ct.default_timezone, 'UTC')) as ts_booking_local_tz,
    v.ts_updated AS ts_visit_updated
  FROM
    datalake_visit.visits AS v
  LEFT JOIN
    datalake_ebdb_user.user AS uv
      ON uv.id = v.id_agent
  LEFT JOIN
    datalake_hub_services.secretariat_hierarchy AS su
      ON su.id_user_5a = v.id_user_visit_request
  LEFT JOIN
    datalake_ebdb_user.user AS u
      ON u.id = v.id_user_visit_request
  LEFT JOIN
    datalake_ebdb_listing.house AS hl
      ON v.id_house = hl.id
  LEFT JOIN
    datalake_ebdb_clean.country AS ct
      ON ct.code = hl.country_code
  WHERE
    v.business_context = 'SALE'
),
sale_events_flow_ranked AS (
  SELECT
    svf.id_visit,
    svf.id_house,
    svf.id_buyer,
    svf.id_agent,
    COALESCE(svf.id_sale_flow, CONCAT(so.id_buyer, '_', so.id_house)) AS id_sales_flow,
    tqc.id_referral_flow,
    so.id_offer,
    svf.first_visit_creation_origin,
    svf.visit_creation_origin,
    svf.visit_code,
    svf.visit_status,
    tqc.tqc_flow,
    CASE
      WHEN tqc.tqc_flow = 'Old'
        THEN 1
      WHEN tqc.tqc_flow = 'New'
        THEN 2
      ELSE NULL
    END AS id_tqc_flow,
    svf.visit_status = 'DONE' AS is_visit_completed,
    CASE
      WHEN tqc.id_user_lead IS NOT NULL
        THEN TRUE
      ELSE FALSE
    END AS is_tqc,
    tqc.ts_created AS ts_tqc_referral,
    svf.ts_visit_scheduled_for,
    svf.ts_first_visit_created,
    svf.ts_visit_created,
    svf.ts_visit_updated,
    so.ts_offer_submitted,
    so.ts_offer_accepted AS ts_offer_accepted,
    so.ts_sale_agreement_created AS ts_sale_agreement_created,
    so.ts_sale_agreement_signed AS ts_sale_agreement_signed,
    ROW_NUMBER() OVER(
      PARTITION BY COALESCE(svf.id_visit, so.id_offer), tqc.id_referral_flow
      ORDER BY
        CASE
          WHEN tqc.tqc_flow = 'Old'
            THEN 1
          WHEN tqc.tqc_flow = 'New'
            THEN 2
          ELSE NULL
        END DESC,
        svf.ts_visit_created,
        so.ts_offer_submitted
    ) AS rn
  FROM
    sale_visit_flows AS svf
  FULL OUTER JOIN
    datalake_sale_offer.sale_offer AS so
      ON svf.id_sale_flow = CONCAT(so.id_buyer, '_', so.id_house)
  LEFT JOIN
    datalake_tqc_referral.unified_lead_referral_flow AS tqc
      ON CONCAT(COALESCE(svf.id_agent, svf.id_user_sale_agent, so.id_agent, so.id_user_agent), '_', COALESCE(svf.id_buyer, so.id_buyer)) = tqc.id_referral_flow
      AND (tqc.status = 'TRUE' OR tqc.status = 'CONFIRMED')
      AND DATE(COALESCE(svf.ts_first_visit_created, so.ts_offer_submitted)) >= DATE(DATE_ADD(tqc.ts_created, -7))
  WHERE
    tqc.id_referral_flow IS NOT NULL
)
SELECT
  id_visit,
  id_house,
  id_buyer,
  id_agent,
  id_sales_flow,
  id_referral_flow,
  id_offer,
  first_visit_creation_origin,
  visit_creation_origin,
  visit_code,
  visit_status,
  tqc_flow,
  id_tqc_flow,
  is_visit_completed,
  is_tqc,
  ts_tqc_referral,
  ts_visit_scheduled_for,
  ts_first_visit_created,
  ts_visit_created,
  ts_visit_updated,
  ts_offer_submitted,
  ts_offer_accepted,
  ts_sale_agreement_created,
  ts_sale_agreement_signed
FROM
  sale_events_flow_ranked
WHERE
  rn = 1
