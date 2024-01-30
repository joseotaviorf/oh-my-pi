WITH sale_supply_cohort_targets AS (
  SELECT
    dt_week AS date,
    dt_week AS week_start,
    week_origin AS weeks_conversion,
    city AS city_group,
    CAST(0 AS INT) AS is_3p_supply,
    CAST(0 AS INT) AS is_3p_demand,
    CAST(NULL AS STRING) AS supply_3p_partner,
    CAST(NULL AS STRING) AS demand_3p_partner,
    mkt_origin,
    NULL AS mkt_channel,
    NULL AS sales_company,
    operation AS lead_processing_operation,
    NULL AS hub_visit,
    NULL AS hub_offer,
    NULL AS first_origin_demand,
    SUM(CAST(REPLACE(OP, ',', '') AS DOUBLE)) AS OP_target,
    SUM(CAST(REPLACE(qualified, ',', '') AS DOUBLE)) AS qualified_target,
    SUM(CAST(REPLACE(available_qualified, ',', '') AS DOUBLE)) AS available_qualified_target,
    SUM(CAST(REPLACE(opportunity, ',', '') AS DOUBLE)) AS opportunity_target,
    SUM(CAST(REPLACE(first_listing, ',', '') AS DOUBLE)) AS first_listing_target
  FROM datalake_gsheets_clean.target_sale_cohort_supply
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
    14,
    15
), sale_demand_cohort_targets AS (
  SELECT
    week AS date,
    week AS week_start,
    week_origin AS weeks_conversion,
    cidade AS city_group,
    CAST(0 AS INT) AS is_3p_supply,
    CAST(0 AS INT) AS is_3p_demand,
    CAST(NULL AS STRING) AS supply_3p_partner,
    CAST(NULL AS STRING) AS demand_3p_partner,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    NULL AS hub_visit,
    operacao AS hub_offer,
    origem AS first_origin_demand,
    SUM(CAST(REPLACE(visit_booked, ',', '') AS DOUBLE)) AS visit_booked_target,
    SUM(CAST(REPLACE(visit_completed, ',', '') AS DOUBLE)) AS visit_completed_target,
    SUM(CAST(REPLACE(offer_sent, ',', '') AS DOUBLE)) AS offer_sent_target,
    SUM(CAST(REPLACE(deal_quali, ',', '') AS DOUBLE)) AS deal_quali_target,
    SUM(CAST(REPLACE(os2ccv, ',', '') AS DOUBLE)) AS os2ccv_target,
    SUM(CAST(REPLACE(offer_accepted, ',', '') AS DOUBLE)) AS offer_accepted_target,
    SUM(CAST(REPLACE(ccv, ',', '') AS DOUBLE)) AS ccv_target
  FROM datalake_gsheets_clean.target_sale_cohort_demand
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
    14,
    15
), sale_cohort_conversions AS (
  SELECT
    date,
    week_start,
    CASE
      WHEN CAST(REPLACE(SPLIT_PART(weeks_conversion, 'W', 2), '+', '') AS INT) <= 0
      THEN 'W0'
      WHEN CAST(REPLACE(SPLIT_PART(weeks_conversion, 'W', 2), '+', '') AS INT) IN (1, 2, 3, 4)
      THEN weeks_conversion
      WHEN CAST(REPLACE(SPLIT_PART(weeks_conversion, 'W', 2), '+', '') AS INT) >= 5
      THEN '+W5'
    END AS weeks_conversion,
    city_group,
    is_3p_supply,
    is_3p_demand,
    supply_3p_partner,
    demand_3p_partner,
    mkt_origin,
    mkt_channel,
    sales_company,
    lead_processing_operation,
    hub_visit,
    hub_offer,
    first_origin_demand,
    SUM(p2fc) AS p2fc,
    SUM(fc2q) AS fc2q,
    SUM(p2q) AS p2q,
    SUM(q2aq) AS q2aq,
    SUM(aq2o) AS aq2o,
    SUM(q2o) AS q2o,
    SUM(o2fl) AS o2fl,
    SUM(fl2ccv) AS fl2ccv,
    SUM(vb2vc) AS vb2vc,
    SUM(vb2os) AS vb2os,
    SUM(vb2oa) AS vb2oa,
    SUM(vb2ccv) AS vb2ccv,
    SUM(vc2ccv) AS vc2ccv,
    SUM(vc2os) AS vc2os,
    SUM(vc2oa) AS vc2oa,
    SUM(os2oa) AS os2oa,
    SUM(os2dq) AS os2dq,
    SUM(dq2oa) AS dq2oa,
    SUM(os2ccv) AS os2ccv,
    SUM(oa2ccv) AS oa2ccv,
    SUM(ccv2lts) AS ccv2lts,
    SUM(lts2lte) AS lts2lte,
    SUM(lte2lrs) AS lte2lrs,
    SUM(lrs2lre) AS lrs2lre,
    SUM(lre2de) AS lre2de,
    SUM(ccv2credstart) AS ccv2credstart,
    SUM(credstart2credsent) AS credstart2credsent,
    SUM(ccv2crnended) AS ccv2crnended,
    SUM(credsent2finstart) AS credsent2finstart,
    SUM(ccv2finstart) AS ccv2finstart,
    SUM(finstart2finended) AS finstart2finended,
    SUM(ccv2mi) AS ccv2mi,
    SUM(mi2ma) AS mi2ma,
    SUM(ccv2ma) AS ccv2ma,
    SUM(ccv2pc) AS ccv2pc
  FROM dw_datamarts.sale_cohort_conversions
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
    14,
    15
)
SELECT
  COALESCE(CAST(sc.date AS DATE), CAST(st.date AS DATE), CAST(sd.date AS DATE)) AS date,
  COALESCE(
    CAST(sc.week_start AS DATE),
    CAST(st.week_start AS DATE),
    CAST(sd.week_start AS DATE)
  ) AS week_start,
  COALESCE(sc.weeks_conversion, st.weeks_conversion, sd.weeks_conversion) AS weeks_conversion,
  COALESCE(sc.city_group, st.city_group, sd.city_group) AS city_group,
  COALESCE(sc.is_3p_supply, st.is_3p_supply, sd.is_3p_supply) AS is_3p_supply,
  COALESCE(sc.is_3p_demand, st.is_3p_demand, sd.is_3p_demand) AS is_3p_demand,
  COALESCE(sc.supply_3p_partner, st.supply_3p_partner, sd.supply_3p_partner) AS supply_3p_partner,
  COALESCE(sc.demand_3p_partner, st.demand_3p_partner, sd.demand_3p_partner) AS demand_3p_partner,
  COALESCE(sc.mkt_origin, st.mkt_origin, sd.mkt_origin) AS mkt_origin,
  COALESCE(sc.mkt_channel, st.mkt_channel, sd.mkt_channel) AS mkt_channel,
  COALESCE(sc.sales_company, st.sales_company, sd.sales_company) AS sales_company,
  COALESCE(
    sc.lead_processing_operation,
    st.lead_processing_operation,
    sd.lead_processing_operation
  ) AS lead_processing_operation,
  COALESCE(sc.hub_visit, st.hub_visit, sd.hub_visit) AS hub_visit,
  COALESCE(sc.hub_offer, st.hub_offer, sd.hub_offer) AS hub_offer,
  COALESCE(sc.first_origin_demand, st.first_origin_demand, sd.first_origin_demand) AS first_origin_demand,
  p2fc AS p2fc,
  fc2q AS fc2q,
  p2q AS p2q,
  q2aq AS q2aq,
  aq2o AS aq2o,
  q2o AS q2o,
  o2fl AS o2fl,
  fl2ccv AS fl2ccv,
  vb2vc AS vb2vc,
  vb2os AS vb2os,
  vb2oa AS vb2oa,
  vb2ccv AS vb2ccv,
  vc2ccv AS vc2ccv,
  vc2os AS vc2os,
  vc2oa AS vc2oa,
  os2oa AS os2oa,
  os2dq AS os2dq,
  dq2oa AS dq2oa,
  os2ccv AS os2ccv,
  oa2ccv AS oa2ccv,
  ccv2lts AS ccv2lts,
  lts2lte AS lts2lte,
  lte2lrs AS lte2lrs,
  lrs2lre AS lrs2lre,
  lre2de AS lre2de,
  ccv2credstart AS ccv2credstart,
  credstart2credsent AS credstart2credsent,
  ccv2crnended AS ccv2crnended,
  credsent2finstart AS credsent2finstart,
  ccv2finstart AS ccv2finstart,
  finstart2finended AS finstart2finended,
  ccv2mi AS ccv2mi,
  mi2ma AS mi2ma,
  ccv2ma AS ccv2ma,
  ccv2pc AS ccv2pc,
  OP_target AS prospect_target,
  qualified_target,
  opportunity_target,
  first_listing_target,
  visit_booked_target,
  visit_completed_target,
  offer_sent_target,
  deal_quali_target,
  os2ccv_target,
  offer_accepted_target,
  ccv_target
FROM sale_cohort_conversions AS sc
FULL OUTER JOIN sale_supply_cohort_targets AS st
  ON sc.date = st.date
  AND sc.week_start = st.week_start
  AND sc.weeks_conversion = st.weeks_conversion
  AND sc.city_group = st.city_group
  AND sc.is_3p_supply = st.is_3p_supply
  AND sc.is_3p_demand = st.is_3p_demand
  AND sc.supply_3p_partner = st.supply_3p_partner
  AND sc.demand_3p_partner = st.demand_3p_partner
  AND sc.mkt_origin = st.mkt_origin
  AND sc.mkt_channel = st.mkt_channel
  AND sc.sales_company = st.sales_company
  AND sc.lead_processing_operation = st.lead_processing_operation
  AND sc.hub_visit = st.hub_visit
  AND sc.hub_offer = st.hub_offer
  AND sc.first_origin_demand = st.first_origin_demand
FULL OUTER JOIN sale_demand_cohort_targets AS sd
  ON sc.date = CAST(sd.date AS DATE)
  AND sc.week_start = CAST(sd.week_start AS DATE)
  AND sc.weeks_conversion = sd.weeks_conversion
  AND sc.city_group = sd.city_group
  AND sc.is_3p_supply = sd.is_3p_supply
  AND sc.is_3p_demand = sd.is_3p_demand
  AND sc.supply_3p_partner = sd.supply_3p_partner
  AND sc.demand_3p_partner = sd.demand_3p_partner
  AND sc.mkt_origin = sd.mkt_origin
  AND sc.mkt_channel = sd.mkt_channel
  AND sc.sales_company = sd.sales_company
  AND sc.lead_processing_operation = sd.lead_processing_operation
  AND sc.hub_visit = sd.hub_visit
  AND sc.hub_offer = sd.hub_offer
  AND sc.first_origin_demand = sd.first_origin_demand