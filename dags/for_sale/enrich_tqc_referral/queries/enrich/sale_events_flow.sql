WITH 
first_booking_author AS (
    SELECT DISTINCT
        bsc.id_booking,
        FIRST_VALUE(id_user) OVER (
          PARTITION BY bsc.id_booking ORDER BY id
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS id_user_creation
    FROM
        datalake_ebdb_clean.booking_status_change AS bsc
),
visit_origin AS (
    SELECT
        v.id AS id_visit,
        v.code,
        vo_update.name AS last_update_source
    FROM
        datalake_ebdb_clean.visit AS v
    LEFT JOIN
        datalake_ebdb_clean.visit_origin AS vo_update
            ON vo_update.id = v.id_last_update_origin
),
base_booking AS (
SELECT
    b.id_visit,
    b.id_house,
    b.id_visitor AS id_buyer,
    b.id_agent,
    ua.id AS id_user_sale_agent,
    IF(b.business_context = 'SALE',
        CONCAT(b.id_visitor, '_', b.id_house),
        NULL
      ) AS id_sale_flow,
    IF( b.business_context = 'SALE',
        (
          CASE
            WHEN fba.id_user_creation = ua.id THEN 'Agent'
            WHEN fba.id_user_creation = b.id_visitor THEN 'Buyer'
            WHEN fba.id_user_creation = su.id_user_5a THEN 'Secretaria'
            WHEN u.email LIKE '%quintoandar.com.br' THEN 'Admin/CX'
            ELSE 'Other'
          END
        ),
        NULL
      ) AS user_sale_booking_creator,
    FROM_UTC_TIMESTAMP(b.ts_created, COALESCE(ct.default_timezone, 'UTC')) AS ts_created_local_tz,
    vo.last_update_source,
    vo.code AS visit_code,
    CASE
      WHEN b.status = 'Realizado' AND b.visit_fup IN ('EntradaNaoAutorizada','NaoCompareceu')
        THEN 'Cancelado'
      ELSE b.status
    END AS visit_status,
    COALESCE(ct.default_timezone, 'UTC') AS default_timezone,
    CAST(b.dt_booking AS TIMESTAMP)
          + FLOOR((b.slot_day * 15 / 60)+8) * INTERVAL 1 HOURS
          + ABS(b.slot_day * 15 % 60) * INTERVAL 1 MINUTES
        AS ts_booking_local_tz,
    b.ts_updated
  FROM
    datalake_ebdb_clean.booking AS b
  LEFT JOIN
    first_booking_author AS fba
      ON fba.id_booking = b.id 
  LEFT JOIN
    visit_origin AS vo
        ON b.id_visit = vo.id_visit        
  LEFT JOIN
    datalake_ebdb_clean.user AS ua
      ON ua.id_agent = b.id_agent
  LEFT JOIN
    datalake_hub_services.secretariat_hierarchy AS su
      ON su.id_user_5a = fba.id_user_creation
  LEFT JOIN
    datalake_ebdb_user.user AS u
      ON u.id = fba.id_user_creation
  LEFT JOIN
    datalake_ebdb_listing.house AS hl
      ON b.id_house = hl.id    
  LEFT JOIN
    datalake_ebdb_clean.country AS ct
      ON ct.code = hl.country_code     
  WHERE
    b.type = 'Visita'
    AND b.business_context = 'SALE'
),
sale_visit_flows AS (
SELECT 
  id_visit,
  id_house,
  id_buyer,
  id_agent,
  id_user_sale_agent,
  id_sale_flow,
  FIRST_VALUE(user_sale_booking_creator) OVER(PARTITION BY id_visit ORDER BY ts_created_local_tz) AS first_visit_creation_origin,
  user_sale_booking_creator AS visit_creation_origin,
  last_update_source AS visit_update_origin,
  ts_created_local_tz AS ts_visit_created,
  visit_code,
  visit_status,
  TO_UTC_TIMESTAMP(ts_booking_local_tz, default_timezone) AS ts_visit_scheduled_for,
  FIRST_VALUE(ts_created_local_tz) OVER(PARTITION BY id_visit ORDER BY ts_created_local_tz) AS ts_first_visit_created,
  ts_updated AS ts_visit_updated
FROM 
  base_booking
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY ts_updated DESC) = 1
)
SELECT
    svf.id_visit,
    svf.id_house,
    svf.id_buyer,
    svf.id_agent,
    COALESCE(svf.id_sale_flow, so.id_sale_flow) AS id_sales_flow,
    tqc.id_referral_flow,
    so.id_offer,
    svf.first_visit_creation_origin,
    svf.visit_creation_origin,
    svf.visit_update_origin,
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
    svf.visit_status = 'Realizado' AS is_visit_completed,
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
    so.dt_offer_accepted AS ts_offer_accepted,
    so.dt_sale_agreement_created AS ts_sale_agreement_created,
    so.dt_sale_agreement_signed AS ts_sale_agreement_signed
  FROM
    sale_visit_flows AS svf
  FULL OUTER JOIN
    datalake_offer.sale_offer AS so
      ON svf.id_sale_flow = so.id_sale_flow
  LEFT JOIN
    datalake_tqc_referral.unified_lead_referral_flow AS tqc
      ON CONCAT(COALESCE(svf.id_agent,svf.id_user_sale_agent,so.id_agent,so.id_user_agent),'_',COALESCE(svf.id_buyer, so.id_buyer)) = tqc.id_referral_flow
    AND (tqc.status = 'TRUE' OR tqc.status = 'CONFIRMED')
    AND DATE(COALESCE(svf.ts_first_visit_created, so.ts_offer_submitted)) >= DATE(DATE_ADD(tqc.ts_created,-7))
  WHERE
    tqc.id_referral_flow IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY COALESCE(svf.id_visit,so.id_offer), id_referral_flow ORDER BY id_tqc_flow DESC, svf.ts_visit_created, so.ts_offer_submitted) = 1