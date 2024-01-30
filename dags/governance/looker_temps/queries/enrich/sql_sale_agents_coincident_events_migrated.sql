WITH cte_aux AS (
  SELECT
    ac.id_agent,
    ac.id_work_contract,
    wc.contract_name,
    NULLIF(wc.`3p_partner`, '') AS demand_3p_partner,
    aacc.is_agent_active AS has_active_contract,
    ac.ts_work_contract_started,
    ac.ts_work_contract_ended,
    GREATEST(
      COALESCE(aacc.ts_revision, DATE(CAST('2000-01-01' AS DATE))),
      COALESCE(ac.ts_work_contract_started, DATE(CAST('2000-01-01' AS DATE)))
    ) AS ts_status_started
  FROM datalake_ebdb_agents.agent_contract AS ac
  LEFT JOIN datalake_ebdb_agents.agents_activations_suspensions_contracts_changes AS aacc
    ON ac.id_agent = aacc.id_agent
    AND aacc.ts_revision >= ac.ts_work_contract_started
    AND aacc.ts_revision < COALESCE(ac.ts_work_contract_ended, CURRENT_TIMESTAMP())
  LEFT JOIN datalake_ebdb_work_contract.work_contract AS wc
    ON wc.id = ac.id_work_contract
), agents_changes AS (
  SELECT
    c.*,
    LEAD(ts_status_started, 1) OVER (PARTITION BY id_agent ORDER BY ts_status_started NULLS LAST) AS ts_status_ended
  FROM cte_aux AS c
), visits AS (
  SELECT DISTINCT
    fv.sk_booking,
    fv.sk_agent,
    fv.sk_region,
    fv.sk_house,
    db.is_3p_demand,
    db.partner_3p_demand,
    db.is_3p_supply,
    db.partner_3p_supply,
    ap.id_work_contract,
    ap.contract_name,
    ap.ts_work_contract_started,
    ap.ts_work_contract_ended,
    fv.sk_booking_created_date,
    fv.sk_visit_completed_date
  FROM dw_sale.fact_visits AS fv
  INNER JOIN dw_public.dim_booking AS db
    ON fv.sk_booking = db.sk_booking
  LEFT JOIN agents_changes AS ap
    ON fv.sk_agent = ap.id_agent
    AND db.dt_created BETWEEN ap.ts_status_started AND COALESCE(ap.ts_status_ended, CURRENT_TIMESTAMP())
), offers AS (
  SELECT DISTINCT
    fo.sk_offer,
    fo.sk_agent,
    fo.sk_region,
    fo.sk_house,
    sdo.is_3p_demand,
    sdo.partner_3p_demand,
    sdo.is_3p_supply,
    sdo.partner_3p_supply,
    v.id_work_contract,
    v.contract_name,
    v.ts_work_contract_started,
    v.ts_work_contract_ended,
    fo.sk_offer_submitted_date,
    fo.sk_offer_accepted_date,
    fo.sk_sale_agreement_signed_date
  FROM dw_sale.fact_offers AS fo
  INNER JOIN dw_sale.dim_offer AS sdo
    ON fo.sk_offer = sdo.sk_offer
  INNER JOIN visits AS v
    ON fo.sk_booking = v.sk_booking
), date_agent AS (
  SELECT
    dd.sk_date,
    dd.date,
    dd.week_start,
    dd.month_start,
    dd.weekday_name,
    CASE WHEN dd.date = dd.month_end THEN TRUE ELSE FALSE END AS is_last_day_of_month,
    ap.id_agent,
    ap.id_work_contract,
    ap.ts_work_contract_started,
    ap.ts_work_contract_ended,
    ap.has_active_contract,
    ap.ts_status_started,
    COUNT(DISTINCT vb.sk_booking) AS had_visit,
    ROW_NUMBER() OVER (PARTITION BY ap.id_agent, dd.date ORDER BY ts_status_started DESC) AS rn
  FROM agents_changes AS ap
  INNER JOIN dw_public.dim_date AS dd
    ON dd.date BETWEEN DATE(ap.ts_status_started) AND COALESCE(DATE(ap.ts_status_ended), CURRENT_TIMESTAMP())
  LEFT JOIN visits AS vb
    ON ap.id_agent = vb.sk_agent
    AND dd.sk_date = vb.sk_booking_created_date
    AND ap.id_work_contract = vb.id_work_contract
    AND ap.ts_work_contract_started = vb.ts_work_contract_started
  WHERE
    dd.sk_date > 0 AND dd.date < CURRENT_DATE
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
), ongoing_agents AS (
  SELECT
    *
  FROM date_agent
  WHERE
    rn = 1 AND has_active_contract
), week_agent AS (
  SELECT
    week_start,
    id_agent,
    SUM(had_visit) > 0 AS had_visits_in_the_week,
    LAG(SUM(had_visit) > 0, 1) OVER (PARTITION BY id_agent ORDER BY week_start NULLS LAST) AS had_visits_last_week
  FROM date_agent
  GROUP BY
    1,
    2
), month_agent AS (
  SELECT
    month_start,
    id_agent,
    SUM(had_visit) > 0 AS had_visits_in_the_month,
    LAG(SUM(had_visit) > 0, 1) OVER (PARTITION BY id_agent ORDER BY month_start NULLS LAST) AS had_visits_last_month
  FROM date_agent
  GROUP BY
    1,
    2
), base AS (
  /* ----------------- */ /* Visits Booked -- */ /* ----------------- */
  SELECT
    'visit booked' AS event,
    sk_booking_created_date AS sk_date,
    sk_agent,
    sk_region,
    sk_house,
    is_3p_demand,
    partner_3p_demand,
    is_3p_supply,
    partner_3p_supply,
    id_work_contract,
    ts_work_contract_started,
    ts_work_contract_ended,
    CAST(sk_booking AS STRING) AS sk_event
  FROM visits
  UNION ALL
  /* -------------------- */ /* Visits Completed -- */ /* -------------------- */
  SELECT
    'visit completed' AS event,
    sk_visit_completed_date AS sk_date,
    sk_agent,
    sk_region,
    sk_house,
    is_3p_demand,
    partner_3p_demand,
    is_3p_supply,
    partner_3p_supply,
    id_work_contract,
    ts_work_contract_started,
    ts_work_contract_ended,
    CAST(sk_booking AS STRING) AS sk_event
  FROM visits
  WHERE
    sk_visit_completed_date > 0
  UNION ALL
  /* -------------------- */ /* Offers Submitted -- */ /* -------------------- */
  SELECT
    'offer submitted' AS event,
    sk_offer_submitted_date AS sk_date,
    sk_agent,
    sk_region,
    sk_house,
    is_3p_demand,
    partner_3p_demand,
    is_3p_supply,
    partner_3p_supply,
    id_work_contract,
    ts_work_contract_started,
    ts_work_contract_ended,
    CAST(sk_offer AS STRING) AS sk_event
  FROM offers
  WHERE
    sk_offer_submitted_date > 0
  UNION ALL
  /* ------------------- */ /* Offers Accepted -- */ /* ------------------- */
  SELECT
    'offer accepted' AS event,
    sk_offer_accepted_date AS sk_date,
    sk_agent,
    sk_region,
    sk_house,
    is_3p_demand,
    partner_3p_demand,
    is_3p_supply,
    partner_3p_supply,
    id_work_contract,
    ts_work_contract_started,
    ts_work_contract_ended,
    CAST(sk_offer AS STRING) AS sk_event
  FROM offers
  WHERE
    sk_offer_accepted_date > 0
  UNION ALL
  /* -------------------------- */ /* Sale Agreements Signed -- */ /* -------------------------- */
  SELECT
    'sale agreement signed' AS event,
    sk_sale_agreement_signed_date AS sk_date,
    sk_agent,
    sk_region,
    sk_house,
    is_3p_demand,
    partner_3p_demand,
    is_3p_supply,
    partner_3p_supply,
    id_work_contract,
    ts_work_contract_started,
    ts_work_contract_ended,
    CAST(sk_offer AS STRING) AS sk_event
  FROM offers
  WHERE
    sk_sale_agreement_signed_date > 0
), events_coincident AS (
  SELECT
    dd.date,
    b.*
  FROM base AS b
  INNER JOIN dw_public.dim_date AS dd
    ON b.sk_date = dd.sk_date
)
SELECT
  COALESCE(da.date, b.date) AS dt_event,
  da.has_active_contract,
  da.weekday_name,
  da.is_last_day_of_month,
  COALESCE(da.id_agent, b.sk_agent) AS sk_agent,
  COALESCE(wa.had_visits_in_the_week, FALSE) AS had_visits_in_the_week,
  COALESCE(wa.had_visits_last_week, FALSE) AS had_visits_last_week,
  COALESCE(ma.had_visits_in_the_month, FALSE) AS had_visits_in_the_month,
  COALESCE(ma.had_visits_last_month, FALSE) AS had_visits_last_month,
  b.sk_region,
  b.sk_house,
  b.is_3p_demand,
  b.partner_3p_demand,
  b.is_3p_supply,
  b.partner_3p_supply,
  COALESCE(da.id_work_contract, b.id_work_contract) AS id_work_contract,
  COALESCE(da.ts_work_contract_started, b.ts_work_contract_started) AS ts_work_contract_start,
  COALESCE(da.ts_work_contract_ended, b.ts_work_contract_ended) AS ts_work_contract_end,
  COUNT(DISTINCT CASE WHEN event = 'visit booked' THEN sk_event END) AS visits_booked,
  COUNT(DISTINCT CASE WHEN event = 'visit completed' THEN sk_event END) AS visits_completed,
  COUNT(DISTINCT CASE WHEN event = 'offer submitted' THEN sk_event END) AS offers_submitted,
  COUNT(DISTINCT CASE WHEN event = 'offer accepted' THEN sk_event END) AS offers_accepted,
  COUNT(DISTINCT CASE WHEN event = 'sale agreement signed' THEN sk_event END) AS sale_agreements_signed,
  DATEDIFF(
    DAY,
    CAST(DATE(COALESCE(da.ts_work_contract_started, b.ts_work_contract_started)) AS TIMESTAMP),
    CAST(MIN(
      CASE
        WHEN COALESCE(COUNT(DISTINCT CASE WHEN event = 'visit booked' THEN sk_event END), 0) > 0
        THEN COALESCE(da.date, b.date)
      END
    ) OVER (PARTITION BY COALESCE(da.id_agent, b.sk_agent), COALESCE(da.ts_work_contract_started, b.ts_work_contract_started)) AS TIMESTAMP)
  ) AS days_to_activation
FROM ongoing_agents AS da
LEFT JOIN week_agent AS wa
  ON da.id_agent = wa.id_agent AND da.week_start = wa.week_start
LEFT JOIN month_agent AS ma
  ON da.id_agent = ma.id_agent AND da.month_start = ma.month_start
FULL JOIN events_coincident AS b
  ON da.id_agent = b.sk_agent AND da.date = b.date AND da.id_work_contract = b.id_work_contract
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
  15,
  16,
  17,
  18