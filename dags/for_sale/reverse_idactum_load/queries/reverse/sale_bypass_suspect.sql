WITH vsl AS (
  SELECT
    visitslog.id_schedule AS sk_booking,
    COALESCE(UPPER(MIN_BY(visitslog.author_user_role, visitslog.ts_created)), 'NONE') AS requested_by
  FROM
    datalake_ebdb_clean.visit_status_log AS visitslog
  WHERE
    DATE(visitslog.ts_created) BETWEEN DATE('2021-01-01') AND DATE_SUB(CURRENT_DATE(), 1)
  GROUP BY
    visitslog.id_schedule
),
bookings AS (
  SELECT
    db.sk_booking,
    db.id_visit AS sk_visit,
    db.id_visitor AS sk_prospect,
    db.id_agent AS sk_agent,
    db.id_property AS sk_house,
    h.id_user AS sk_owner,
    h.id_region AS sk_region,
    h.is_sale_primary_market,
    db.dt_created,
    db.dt_scheduling AS dt_scheduled,
    db.dt_cancel AS dt_canceled,
    UPPER(db.status) AS status,
    COALESCE(UPPER(h.key_location), 'NONE') AS entrance_method,
    IF(db.is_3p_supply, '3p', '1p') AS supply,
    IF(db.is_3p_demand, '3p', '1p') AS demand,
    IF(
      UPPER(db.visit_intent) = 'RENT',
      'RENT',
      'SALE'
    ) AS business_context,
    dr.country_name AS country,
    dr.city_name AS city,
    dr.city_group,
    vsl.requested_by,
    CASE
      WHEN DATE(db.dt_scheduling) > DATE_SUB(CURRENT_DATE(), 1) THEN 0
      WHEN UPPER(db.status) = 'REALIZADO'
        AND db.successful_entrance = '1'
        AND db.is_visit_completed THEN 1
      WHEN UPPER(db.status) = 'REALIZADO'
        AND NOT db.is_visit_completed THEN 2
      WHEN UPPER(db.status) = 'CANCELADO'
        OR vcu.id_visit IS NOT NULL THEN 3
      WHEN DATE(db.dt_scheduling) < DATE_SUB(CURRENT_DATE(), 1)
        AND NOT UPPER(db.status) = 'REALIZADO' THEN 4
      ELSE NULL
    END AS computed_status,
    COALESCE(
      UPPER(vcu.on_behalf_of),
      UPPER(db.responsible)
    ) AS cancelled_by,
    COALESCE(
      TRIM(UPPER(vcu.reason)),
      UPPER(db.cancellation_reason),
      TRIM(UPPER(db.reason))
    ) AS cancellation_reason,
    IF(
      UPPER(v.type) = 'TENTANT'
      AND v.has_attended = FALSE,
      1,
      0
    ) AS visitor_no_show,
    IF(
      db.dt_scheduling < db.dt_created,
      1,
      0
    ) AS visit_registered_by_agent,
    IF(db.is_rescheduled, 1, 0) AS visit_rescheduled
  FROM
    dw_public.dim_booking AS db
  INNER JOIN
    datalake_ebdb_listing.house AS h
      ON h.id = db.id_property
  INNER JOIN
    dw_public.dim_region AS dr
      ON dr.sk_region = h.id_region
  LEFT JOIN
    datalake_visit.visit_cancellation_unified AS vcu
      ON vcu.id_visit = db.id_visit
  LEFT JOIN
    datalake_ebdb_clean.visitor AS v
      ON v.id_booking = db.sk_booking
      AND v.id_user = db.id_visitor
  LEFT JOIN
    vsl
      ON vsl.sk_booking = db.sk_booking
  WHERE
    UPPER(db.type) = 'VISITA'
    AND UPPER(db.visit_intent) IN ('SALE', 'RENT')
    AND DATE(db.dt_created) BETWEEN DATE('2021-01-01') AND DATE_SUB(CURRENT_DATE(), 1)
    AND db.id_property NOT IN (
      893768094,
      893073206,
      892819617,
      894328259,
      894328325,
      894328313
    )
),
computed_visits AS (
  SELECT DISTINCT
    UPPER(dv.visit_code) AS visit_code,
    b.sk_booking,
    b.sk_visit,
    b.sk_prospect,
    b.sk_agent,
    b.sk_house,
    b.sk_owner,
    b.sk_region,
    b.is_sale_primary_market,
    b.dt_created as created_at,
    b.dt_scheduled,
    IF(
      MIN(b.computed_status) OVER (PARTITION BY b.sk_visit) = 3,
      COALESCE(b.dt_canceled, b.dt_scheduled),
      NULL
    ) AS cancelled_at,
    b.status,
    CASE MIN(b.computed_status) OVER (PARTITION BY b.sk_visit)
      WHEN 0 THEN 'SCHEDULED'
      WHEN 1 THEN 'COMPLETED'
      WHEN 2 THEN 'UNSUCCESSFUL'
      WHEN 3 THEN 'CANCELLED'
      WHEN 4 THEN 'STALLED'
      ELSE 'OTHER'
    END AS computed_status,
    UPPER(b.supply) AS supply,
    UPPER(b.demand) AS demand,
    b.business_context,
    b.country,
    b.city,
    b.city_group,
    IF(
      MIN(b.computed_status) OVER (PARTITION BY b.sk_visit) = 1,
      1,
      0
    ) AS visit_completed,
    IF(
      MIN(b.computed_status) OVER (PARTITION BY b.sk_visit) = 2,
      1,
      0
    ) AS visit_unsuccessful,
    IF(
      MIN(b.computed_status) OVER (PARTITION BY b.sk_visit) = 3,
      1,
      0
    ) AS visit_cancelled,
    IF(
      MIN(b.computed_status) OVER (PARTITION BY b.sk_visit) = 3,
      COALESCE(
        MAX(b.cancelled_by) OVER (PARTITION BY b.sk_visit),
        'UNKNOWN'
      ),
      'NONE'
    ) AS cancelled_by,
    IF(
      MIN(b.computed_status) OVER (PARTITION BY b.sk_visit) = 3,
      COALESCE(
        MAX(b.cancellation_reason) OVER (PARTITION BY b.sk_visit),
        'UNKNOWN'
      ),
      'NONE'
    ) AS cancellation_reason,
    MAX(b.visitor_no_show) OVER (PARTITION BY b.sk_visit) AS visitor_no_show,
    b.visit_registered_by_agent,
    b.visit_rescheduled,
    b.requested_by
  FROM
    bookings AS b
  LEFT JOIN
    dw_visit.dim_visit AS dv
      ON dv.sk_visit = b.sk_visit
),
confirmed_by_cases_zendesk AS (
  SELECT
    ELEMENT_AT(e.custom_fields_map, '[BP] Offer CCV') AS sk_offer,
    ELEMENT_AT(e.custom_fields_map, '[BP] ID do imóvel') AS sk_house
  FROM
    dw_customer_support.dim_ticket AS e
  LEFT JOIN
    dw_customer_support.fact_tickets AS t
      ON t.sk_ticket = CAST(e.sk_ticket AS BIGINT)
  WHERE
    e.group_name IN (
      'Canal de denúncia [FS] [Bypass]',
      'Recuperação de valores [FS] [Bypass]',
      'Estudo de matrícula [FS] [Bypass]'
    )
    AND ELEMENT_AT(e.custom_fields_map, '[BP] ID do imóvel') IS NOT NULL
    AND e.tags NOT LIKE '%comunicacao_cr%'
    AND e.tags NOT LIKE '%fsbp_legado%'
    AND ELEMENT_AT(e.custom_fields_map, '[BP] Houve bypass?') LIKE '%sim%'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ELEMENT_AT(e.custom_fields_map, '[BP] ID do imóvel') ORDER BY t.ts_created) = 1
),
last_listing_status AS (
  SELECT
    dl.sk_sale_listing,
    dl.sk_house,
    fl.sk_owner,
    dl.status AS listing_status,
    dl.ts_last_depublication,
    dl.unpublished_reason,
    dl.closing_status
  FROM
    dw_sale.dim_listing AS dl
  INNER JOIN
    dw_sale.fact_listings AS fl
      ON dl.sk_house = fl.sk_house
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY dl.sk_sale_listing ORDER BY dl.ts_created DESC) = 1
),
listings AS (
  SELECT
    sk_sale_listing,
    sk_house,
    sk_owner,
    listing_status,
    ts_last_depublication
  FROM
    last_listing_status
  WHERE
    listing_status = 'UNPUBLISHED'
    AND (
      unpublished_reason IS NULL
      OR unpublished_reason NOT IN ('DUPLICATED_HOUSE')
    )
    AND (
      closing_status IS NULL
      OR closing_status NOT IN ('SALE_COMPLETED', 'CCV_SIGNED')
    )
    AND ts_last_depublication >= DATE('2021-10-01')
),
visits AS (
  SELECT
    sk_visit,
    business_context,
    sk_house,
    sk_owner,
    sk_prospect,
    computed_status AS visit_status,
    dt_scheduled AS visit_scheduled_to,
    cancelled_at AS visit_cancelled_at
  FROM
    computed_visits
  WHERE
      UPPER(computed_status) = 'COMPLETED'
      OR UPPER(computed_status) = 'CANCELLED'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY sk_house, sk_prospect ORDER BY dt_scheduled DESC) = 1
),
sales_flow AS (
  SELECT
    fo.sk_offer,
    fo.sk_house,
    fo.sk_owner,
    fo.sk_buyer,
    fo.ts_offer_submitted,
    fo.ts_offer_accepted,
    dsa.ts_sale_agreement_signed,
    do.offer_status,
    dsa.sale_agreement_status
  FROM
    dw_sale.dim_offer AS do
  INNER JOIN
    dw_sale.fact_offers AS fo
      ON do.sk_offer = fo.sk_offer
  LEFT JOIN
    dw_sale.dim_sale_agreement AS dsa
      ON do.sk_offer = dsa.sk_offer
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY fo.sk_house, fo.sk_buyer ORDER BY fo.ts_offer_submitted DESC) = 1
),
agg_sales_flow AS (
  SELECT
    sk_house,
    CASE
      WHEN COUNT(sk_offer) FILTER (WHERE ts_sale_agreement_signed IS NOT NULL) > 0 THEN TRUE
      ELSE FALSE
    END AS has_signed_ccv
  FROM
    sales_flow
  GROUP BY
    sk_house
),
payments AS (
  SELECT
    st.id AS id_sale_transaction,
    s.id_external_offer AS sk_offer,
    ir.income_from,
    st.event,
    st.status,
    ir.amount AS income_amount,
    ir.dt_income
  FROM
    datalake_monopoly_clean.sale_transaction AS st
  LEFT JOIN
    datalake_monopoly_clean.sale AS s
      ON st.id_sale = s.id
  LEFT JOIN
    datalake_monopoly_clean.income_reference AS ir
      ON st.id_income_reference = ir.id
  LEFT JOIN
    datalake_monopoly_clean.income AS i
      ON ir.id_income = i.id
  WHERE
    UPPER(i.status) != 'CANCELED'
),
agg_payments AS (
  SELECT
    sk_offer,
    CASE
      WHEN COUNT(DISTINCT id_sale_transaction) > 0 THEN TRUE
      ELSE FALSE
    END AS has_income_transactions
  FROM
    payments
  GROUP BY
    sk_offer
),
house_address AS (
  SELECT
    id_house,
    house_city,
    house_zipcode,
    house_address,
    house_number,
    house_complement,
    house_neighborhood,
    house_type,
    house_garages,
    house_total_area,
    house_lat,
    house_lng
  FROM
    dw_public.dim_house_listing
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_publication DESC) = 1
),
consolidated AS (
  SELECT
    l.sk_sale_listing,
    l.sk_house,
    COALESCE(asf.has_signed_ccv, FALSE) AS has_signed_ccv,
    COALESCE(ap.has_income_transactions, FALSE) AS has_income_transactions,
    ha.house_city,
    ha.house_zipcode,
    ha.house_address,
    ha.house_number,
    ha.house_complement,
    ha.house_neighborhood,
    ha.house_type,
    ha.house_garages,
    ha.house_total_area,
    h.construction_year,
    ha.house_lat,
    ha.house_lng,
    l.sk_owner,
    d_owner.nome AS owner_name,
    d_owner.cpf AS owner_cpf,
    l.listing_status,
    v.sk_visit,
    v.business_context,
    v.visit_status,
    v.sk_prospect,
    d_prospect.nome AS prospect_name,
    d_prospect.cpf AS prospect_cpf,
    sf.sk_offer,
    DATE(l.ts_last_depublication) AS dt_last_depublication,
    DATE(v.visit_scheduled_to) AS dt_visit_scheduled,
    DATE(v.visit_cancelled_at) AS dt_visit_cancelled,
    DATE(sf.ts_offer_submitted) AS dt_offer_submitted,
    DATE(sf.ts_offer_accepted) AS dt_offer_accepted,
    DATE(sf.ts_sale_agreement_signed) AS dt_sale_agreement_signed,
    sf.offer_status,
    sf.sale_agreement_status,
    CASE
      WHEN sf.ts_sale_agreement_signed IS NOT NULL THEN 'CCV'
      WHEN sf.ts_offer_accepted IS NOT NULL THEN 'OA'
      WHEN sf.ts_offer_submitted IS NOT NULL THEN 'OS'
      WHEN v.visit_scheduled_to IS NOT NULL THEN 'VC'
      ELSE NULL
    END AS status_5A,
    CASE
      WHEN fl3p.sk_lead_3p IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_3p_lead
  FROM
    listings AS l
  LEFT JOIN
    visits AS v
      ON l.sk_house = v.sk_house
  LEFT JOIN
    sales_flow AS sf
      ON l.sk_house = sf.sk_house
      AND v.sk_prospect = sf.sk_buyer
  LEFT JOIN
    agg_sales_flow AS asf
      ON l.sk_house = asf.sk_house
  LEFT JOIN
    dw_3p_supply.fact_lead_3p_flows AS fl3p
      ON l.sk_house = fl3p.sk_house
      AND fl3p.sk_house != -1
  LEFT JOIN
    agg_payments AS ap
      ON sf.sk_offer = ap.sk_offer
  LEFT JOIN
    dw_public.dim_user AS d_prospect
      ON v.sk_prospect = d_prospect.sk_user
  LEFT JOIN
    dw_public.dim_user AS d_owner
      ON l.sk_owner = d_owner.sk_user
  LEFT JOIN
    house_address AS ha
      ON l.sk_house = ha.id_house
  LEFT JOIN
    datalake_ebdb_clean.house AS h
      ON l.sk_house = h.id
)
SELECT DISTINCT
  c.sk_house,
  sk_visit,
  c.sk_offer,
  status_5A,
  prospect_cpf,
  prospect_name,
  owner_cpf,
  owner_name,
  house_city,
  house_zipcode,
  house_address,
  house_number,
  house_complement,
  house_type,
  construction_year,
  house_total_area,
  house_garages,
  house_lat,
  house_lng,
  dt_visit_scheduled,
  dt_visit_cancelled,
  dt_offer_submitted,
  dt_offer_accepted,
  dt_last_depublication,
  YEAR(CURRENT_DATE()) AS year,
  MONTH(CURRENT_DATE()) AS month,
  DAY(CURRENT_DATE()) AS day
FROM
  consolidated AS c
LEFT JOIN
    confirmed_by_cases_zendesk AS cz
      ON c.sk_house = cz.sk_house
WHERE
  (
    c.sk_visit IS NOT NULL
    OR c.sk_offer IS NOT NULL
  )
  AND c.has_signed_ccv = FALSE
  AND c.is_3p_lead = FALSE
  AND c.has_income_transactions = FALSE
  AND cz.sk_house IS NULL
