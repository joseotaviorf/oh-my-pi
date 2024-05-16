WITH supply_targets AS (
  SELECT
    CAST(REPLACE(CAST(dt_target AS STRING), '-', '') AS BIGINT) AS date_,
    ts.city_group,
    dr.tier,
    dr.country_code,
    CASE WHEN supply_mkt_origin_detailed = 'B2B' THEN TRUE ELSE FALSE END AS is_b2b_supply,
    NULL AS supply_origin,
    CASE
      WHEN supply_mkt_origin_detailed = 'Spinver'
      THEN 'Partners'
      ELSE supply_mkt_origin_detailed
    END AS supply_channel,
    NULL AS lead_context,
    lead_processing_operation,
    NULL AS sales_company,
    NULL AS lead_origin,
    SUM(CAST(REPLACE(prospects, ',', '') AS DOUBLE)) AS prospects_target,
    SUM(CAST(REPLACE(qualifieds, ',', '') AS DOUBLE)) AS qualifieds_target,
    SUM(
      CAST(CASE
        WHEN REPLACE(available_qualifieds, ',', '') = ''
        THEN '0'
        ELSE REPLACE(available_qualifieds, ',', '')
      END AS DOUBLE)
    ) AS available_qualifieds_target,
    SUM(CAST(REPLACE(opportunities, ',', '') AS DOUBLE)) AS opportunities_target,
    SUM(CAST(REPLACE(first_listings, ',', '') AS DOUBLE)) AS first_listings_target
  FROM datalake_gsheets.rental_supply_coincident_targets AS ts
  LEFT JOIN (
    SELECT DISTINCT
      tier,
      city_group,
      country_code
    FROM dw_public.dim_region
    WHERE
      (
        NOT tier IS NULL OR country_code <> 'BR'
      )
    GROUP BY
      1,
      2,
      3
  ) AS dr
    ON dr.city_group = ts.city_group
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11
), demand_targets AS (
  SELECT
    CAST(REPLACE(CAST(dt_target AS STRING), '-', '') AS BIGINT) AS date_,
    td.city_group,
    dr.tier,
    dr.country_code,
    business_type AS is_b2b_demand,
    rent_flow_origin AS funnel_first_touchpoint,
    NULL AS guarantee,
    SUM(CAST(REPLACE(visits_booked, ',', '') AS DOUBLE)) AS visits_booked_target,
    SUM(CAST(REPLACE(visits_completed, ',', '') AS DOUBLE)) AS visits_completed_target,
    SUM(CAST(REPLACE(offers_submitted, ',', '') AS DOUBLE)) AS offer_sent_target,
    SUM(CAST(REPLACE(offers_accepted, ',', '') AS DOUBLE)) AS offer_accepted_target,
    SUM(CAST(REPLACE(evaluation_started, ',', '') AS DOUBLE)) AS evaluation_started_target,
    SUM(CAST(REPLACE(evaluation_positive, ',', '') AS DOUBLE)) AS evaluation_positive_target,
    SUM(CAST(REPLACE(documentation_sent, ',', '') AS DOUBLE)) AS doc_sent_target,
    SUM(CAST(REPLACE(credit_approved, ',', '') AS DOUBLE)) AS credit_approved_target,
    SUM(CAST(REPLACE(contracts_signed, ',', '') AS DOUBLE)) AS contracts_signed_target
  FROM datalake_gsheets.rental_demand_coincident_targets AS td
  LEFT JOIN (
    SELECT DISTINCT
      tier,
      city_group,
      country_code
    FROM dw_public.dim_region
    WHERE
      (
        NOT tier IS NULL OR country_code <> 'BR'
      )
    GROUP BY
      1,
      2,
      3
  ) AS dr
    ON dr.city_group = td.city_group
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7
), ongoing_listing_target AS (
  SELECT
    CAST(REPLACE(CAST(dt_created AS STRING), '-', '') AS BIGINT) AS date_,
    ot.city_group,
    dr.tier,
    dr.country_code,
    NULL AS is_b2b_supply,
    NULL AS is_b2b_demand,
    NULL AS supply_origin,
    NULL AS supply_channel,
    NULL AS lead_context,
    NULL AS lead_processing_operation,
    NULL AS funnel_first_touchpoint,
    NULL AS guarantee,
    NULL AS sales_company,
    NULL AS lead_origin,
    SUM(CAST(REPLACE(CAST(relisting AS STRING),',','') AS DOUBLE)) + SUM(CAST(REPLACE(CAST(recovered AS STRING),',','') AS DOUBLE)) AS relistings_recovered_target,
    SUM(CAST(REPLACE(CAST(ongoing_listings AS STRING), ',', '') AS DOUBLE)) AS ongoing_listing_target
  FROM datalake_gsheets_clean.ongoing_listings_target AS ot
  LEFT JOIN (
    SELECT DISTINCT
      tier,
      city_group,
      country_code
    FROM dw_public.dim_region
    WHERE
      (
        NOT tier IS NULL OR country_code <> 'BR'
      )
    GROUP BY
      1,
      2,
      3
  ) AS dr
    ON dr.city_group = ot.city_group
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14
), ongoing_listing_actual AS (
  SELECT
    CAST(DATE_FORMAT(date, 'yyyyMMdd') AS BIGINT) AS date_,
    dr.city_group,
    dr.tier,
    dr.country_code,
    NULL AS is_b2b_supply,
    NULL AS is_b2b_demand,
    NULL AS supply_origin,
    NULL AS supply_channel,
    NULL AS lead_context,
    NULL AS lead_processing_operation,
    NULL AS funnel_first_touchpoint,
    NULL AS guarantee,
    NULL AS sales_company,
    NULL AS lead_origin,
    SUM(ongoing_listings) AS ongoing_listings
  FROM metric_rent.ongoing_listings_daily_by_sk_region AS me
  LEFT JOIN dw_public.dim_region AS dr
    ON dr.sk_region = me.sk_region
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14
), total_listings_actual AS (
  SELECT
    CAST(DATE_FORMAT(DATE(ts_publication), 'yyyyMMdd') AS BIGINT) AS date_,
    dr.city_group,
    dr.tier,
    dr.country_code,
    NULL AS is_b2b_supply,
    NULL AS is_b2b_demand,
    NULL AS supply_origin,
    NULL AS supply_channel,
    NULL AS lead_context,
    NULL AS lead_processing_operation,
    NULL AS funnel_first_touchpoint,
    NULL AS guarantee,
    NULL AS sales_company,
    NULL AS lead_origin,
    COUNT(DISTINCT dhl.sk_house_listing) AS total_listings
  FROM dw_public.dim_house_listing AS dhl
  LEFT JOIN dw_public.fact_house_listings AS fhl
    ON fhl.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN dw_public.dim_region AS dr
    ON fhl.sk_region = dr.sk_region
  WHERE
    dhl.version <> 0 AND (
      NOT dr.tier IS NULL OR NOT dr.city_group IS NULL
    )
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14
), rental_events AS (
  SELECT
    sk_event_date AS date_,
    dr.city_group,
    CASE
      WHEN dr.city_group IN ('RMSP', 'Rio de Janeiro')
      THEN 1
      WHEN dr.city_group IN ('Campinas', 'Belo Horizonte', 'Brasília', 'Porto Alegre')
      THEN 2
      WHEN dr.city_group IN ('Goiânia', 'Curitiba', 'Florianópolis')
      THEN 3
      ELSE 4
    END AS tier,
    dr.country_code,
    NULL AS is_b2b_supply,
    CASE
      WHEN dhl.is_b2b = TRUE
      THEN 'B2B'
      WHEN dhl.first_consultant_type = 'CIQ_MANAGER'
      THEN 'ASP'
      WHEN dhl.is_for_rent = TRUE
      AND (
        NOT dhl.first_consultant_type IS NULL AND dhl.first_consultant_type <> 'Core'
      )
      THEN dhl.first_consultant_type
      WHEN dhl.is_b2b = FALSE
      OR (
        dhl.first_consultant_type IS NULL OR dhl.first_consultant_type = 'Core'
      )
      THEN 'CORE'
    END AS is_b2b_demand,
    NULL AS supply_mkt_origin,
    NULL AS supply_mkt_origin_detailed,
    NULL AS lead_context,
    NULL AS lead_processing_operation,
    CASE WHEN drf.first_touchpoint = 'DIRECT' THEN drf.first_touchpoint ELSE 'VISIT' END AS first_touchpoint,
    CASE
      WHEN ref.sk_event_type BETWEEN 1 AND 4
      THEN FALSE
      WHEN ref.sk_event_type > 4 AND dp.guarantee = 'RentalGuarantee'
      THEN TRUE
      ELSE FALSE
    END AS is_guarantee,
    NULL AS sales_company,
    NULL AS lead_origin,
    0 AS leads,
    0 AS prospects,
    0 AS qualifieds,
    0 AS available_qualifieds,
    0 AS opportunities,
    0 AS first_listings,
    0 AS messages_sent_tta,
    0 AS registered_agent_supports,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 1) AS visits_booked,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 2) AS visits_completed,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 3) AS offer_submitted,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 4) AS offer_approved,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 5) AS credit_evaluation_init,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 6) AS credit_evaluation_positive,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 7) AS doc_sent,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 8) AS credit_approved,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 10) AS contract_created,
    COUNT(DISTINCT sk_event) FILTER(WHERE
      ref.sk_event_type = 9) AS contract_signed,
    NULL AS contract_ended
  FROM dw_rent.fact_rent_demand_events AS ref
  LEFT JOIN dw_public.dim_date AS dt /* event date */
    ON (
      dt.sk_date = ref.sk_event_date
    )
  LEFT JOIN dw_public.dim_region AS dr /* city_groups */
    ON (
      dr.sk_region = ref.sk_region
    )
  LEFT JOIN dw_public.dim_house_listing AS dhl /* listings info */
    ON ref.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN dw_rent.fact_rent_flows AS frf
    ON ref.sk_rent_flow = frf.sk_rent_flow
  LEFT JOIN dw_rent.dim_rent_flow_type AS drf
    ON frf.sk_rent_flow_type = drf.sk_rent_flow_type
  LEFT JOIN dw_public.dim_proposal AS dp
    ON ref.sk_proposal = dp.sk_proposal
  WHERE
    COALESCE(dr.country_code, 'BR') = 'BR'
    AND dt.date >= CURRENT_DATE - INTERVAL '1' YEAR
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12
), tenant_prospect AS (
  SELECT
    CAST(DATE_FORMAT(dt_event, 'yyyyMMdd') AS BIGINT) AS date_,
    tpt.city_group,
    dr.tier,
    dr.country_code,
    mkt_origin,
    mkt_channel,
    COUNT(DISTINCT (
      CASE WHEN tenant_prospect_order = 1 THEN sk_client ELSE NULL END
    )) AS new_tenant_prospects,
    SUM(new_tenant_prospects_target) AS new_tenant_prospects_target
  FROM dw_datamarts.performance_marketing_metrics_demand AS tpt
  LEFT JOIN (
    SELECT DISTINCT
      tier,
      city_group,
      country_code
    FROM dw_public.dim_region
    WHERE
      (
        NOT tier IS NULL OR country_code <> 'BR'
      )
    GROUP BY
      1,
      2,
      3
  ) AS dr
    ON dr.city_group = tpt.city_group
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6
)
SELECT
  DATE(
    TO_TIMESTAMP(CAST((
      COALESCE(COALESCE(df.date_, st.date_), dt.date_, tp.date_, ola.date_, olt.date_, tla.date_)
    ) AS STRING), 'yyyyMMdd')
  ) AS date,
  COALESCE(df.tier, st.tier, dt.tier, tp.tier, olt.tier, ola.tier, tla.tier) AS tier,
  COALESCE(
    COALESCE(COALESCE(df.city_group, st.city_group), dt.city_group),
    tp.city_group,
    ola.city_group,
    olt.city_group,
    tla.city_group
  ) AS city_group,
  COALESCE(
    COALESCE(COALESCE(df.country_code, st.country_code), dt.country_code),
    tp.country_code,
    ola.country_code,
    olt.country_code,
    tla.country_code
  ) AS country_code,
  COALESCE(
    df.is_b2b_supply,
    st.is_b2b_supply,
    ola.is_b2b_supply,
    olt.is_b2b_supply,
    tla.is_b2b_supply
  ) AS is_b2b_supply,
  COALESCE(
    df.is_b2b_demand,
    dt.is_b2b_demand,
    ola.is_b2b_demand,
    olt.is_b2b_demand,
    tla.is_b2b_demand
  ) AS is_b2b_demand,
  COALESCE(
    df.supply_mkt_origin,
    st.supply_origin,
    tp.mkt_origin,
    ola.supply_origin,
    olt.supply_origin,
    tla.supply_origin
  ) AS mkt_origin,
  COALESCE(
    df.supply_mkt_origin_detailed,
    st.supply_channel,
    tp.mkt_channel,
    ola.supply_channel,
    olt.supply_channel,
    tla.supply_channel
  ) AS mkt_channel,
  COALESCE(df.lead_context, st.lead_context, ola.lead_context, olt.lead_context, tla.lead_context) AS lead_context,
  COALESCE(
    df.first_touchpoint,
    dt.funnel_first_touchpoint,
    ola.funnel_first_touchpoint,
    olt.funnel_first_touchpoint,
    tla.funnel_first_touchpoint
  ) AS first_touchpoint,
  COALESCE(df.is_guarantee, dt.guarantee, ola.guarantee, olt.guarantee, tla.guarantee) AS is_guarantee,
  COALESCE(
    df.lead_processing_operation,
    st.lead_processing_operation,
    ola.lead_processing_operation,
    olt.lead_processing_operation,
    tla.lead_processing_operation
  ) AS lead_processing_operation,
  COALESCE(
    df.sales_company,
    st.sales_company,
    ola.sales_company,
    olt.sales_company,
    tla.sales_company
  ) AS sales_company,
  COALESCE(df.lead_origin, st.lead_origin, ola.lead_origin, olt.lead_origin, tla.lead_origin) AS lead_origin,
  df.leads,
  df.prospects,
  df.qualifieds,
  df.available_qualifieds,
  df.opportunities,
  df.first_listings,
  df.messages_sent_tta,
  df.registered_agent_supports,
  df.visits_booked,
  df.visits_completed,
  df.offer_submitted,
  df.offer_approved,
  df.credit_evaluation_init,
  df.credit_evaluation_positive,
  df.doc_sent,
  df.credit_approved,
  df.contract_created,
  df.contract_signed,
  df.contract_ended,
  tp.new_tenant_prospects,
  ola.ongoing_listings,
  tla.total_listings,
  tp.new_tenant_prospects_target,
  olt.ongoing_listing_target,
  COALESCE(olt.relistings_recovered_target, 0) + COALESCE(first_listings_target, 0) AS total_listings_target,
  st.prospects_target,
  st.qualifieds_target,
  st.available_qualifieds_target,
  st.opportunities_target,
  st.first_listings_target,
  dt.visits_booked_target,
  dt.visits_completed_target,
  dt.offer_sent_target,
  dt.offer_accepted_target,
  dt.evaluation_started_target,
  dt.evaluation_positive_target,
  dt.doc_sent_target,
  dt.credit_approved_target,
  dt.contracts_signed_target,
  CURRENT_DATE AS dt_load
FROM rental_events AS df
FULL OUTER JOIN supply_targets AS st
  ON df.date_ = st.date_
  AND df.city_group = st.city_group
  AND df.tier = st.tier
  AND df.is_b2b_supply = st.is_b2b_supply
  AND df.supply_mkt_origin = st.supply_origin
  AND df.supply_mkt_origin_detailed = st.supply_channel
  AND df.lead_context = st.lead_context
  AND df.lead_processing_operation = st.lead_processing_operation
  AND df.sales_company = st.sales_company
  AND df.lead_origin = st.lead_origin
FULL OUTER JOIN demand_targets AS dt
  ON df.date_ = dt.date_
  AND df.city_group = dt.city_group
  AND df.tier = dt.tier
  AND df.is_b2b_demand = dt.is_b2b_demand
  AND df.first_touchpoint = dt.funnel_first_touchpoint
  AND df.is_guarantee = dt.guarantee
FULL OUTER JOIN tenant_prospect AS tp
  ON df.date_ = tp.date_
  AND df.city_group = tp.city_group
  AND df.tier = tp.tier
  AND df.supply_mkt_origin = tp.mkt_origin
  AND df.supply_mkt_origin_detailed = tp.mkt_channel
FULL OUTER JOIN ongoing_listing_target AS olt
  ON df.date_ = olt.date_
  AND df.city_group = olt.city_group
  AND df.tier = olt.tier
  AND df.is_b2b_supply = olt.is_b2b_supply
  AND df.supply_mkt_origin = olt.supply_origin
  AND df.supply_mkt_origin_detailed = olt.supply_channel
  AND df.lead_context = olt.lead_context
  AND df.is_b2b_demand = olt.is_b2b_demand
  AND df.first_touchpoint = olt.funnel_first_touchpoint
  AND df.is_guarantee = olt.guarantee
  AND df.lead_processing_operation = olt.lead_processing_operation
  AND df.sales_company = olt.sales_company
  AND df.lead_origin = olt.lead_origin
FULL OUTER JOIN ongoing_listing_actual AS ola
  ON df.date_ = ola.date_
  AND df.city_group = ola.city_group
  AND df.tier = ola.tier
  AND df.is_b2b_supply = ola.is_b2b_supply
  AND df.supply_mkt_origin = ola.supply_origin
  AND df.supply_mkt_origin_detailed = ola.supply_channel
  AND df.lead_context = ola.lead_context
  AND df.is_b2b_demand = ola.is_b2b_demand
  AND df.first_touchpoint = ola.funnel_first_touchpoint
  AND df.is_guarantee = ola.guarantee
  AND df.lead_processing_operation = ola.lead_processing_operation
  AND df.sales_company = ola.sales_company
  AND df.lead_origin = ola.lead_origin
FULL OUTER JOIN total_listings_actual AS tla
  ON df.date_ = tla.date_
  AND df.city_group = tla.city_group
  AND df.tier = tla.tier
  AND df.is_b2b_supply = tla.is_b2b_supply
  AND df.supply_mkt_origin = tla.supply_origin
  AND df.supply_mkt_origin_detailed = ola.supply_channel
  AND df.lead_context = tla.lead_context
  AND df.is_b2b_demand = tla.is_b2b_demand
  AND df.first_touchpoint = tla.funnel_first_touchpoint
  AND df.is_guarantee = tla.guarantee
  AND df.lead_processing_operation = tla.lead_processing_operation
  AND df.sales_company = tla.sales_company
  AND df.lead_origin = tla.lead_origin