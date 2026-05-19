WITH visit_fup_vsl AS ( -- This is to handle the case where the visit_fup is not in the booking table (missing data from visit finalization rollout) so the visit finalization is enriched temporarily from visit_status_log table.
  SELECT
    id_visit,
    id_schedule,
    CASE
      WHEN event_type = 'VISIT_DONE' THEN 'VaiNegociar'
      WHEN event_type = 'VISIT_UNSUCCESSFUL' AND reason IN ('DEMAND_DID_NOT_ATTEND_VISIT', 'AGENT_DID_NOT_ATTEND_VISIT', 'SUPPLY_DID_NOT_ATTEND_VISIT') THEN 'NaoCompareceu'
      WHEN event_type = 'VISIT_UNSUCCESSFUL' AND reason IN ('ACCESS_TO_HOUSE_NOT_AUTHORIZED', 'HOUSE_KEYS_NOT_AVAILABLE', 'HOUSE_NO_LONGER_AVAILABLE_FOR_RENT', 'TENANT_LIVING_DID_NOT_ALLOW_VISIT', 'HOUSE_NO_LONGER_AVAILABLE_FOR_SALE') THEN 'EntradaNaoAutorizada'
    END AS visit_fup,
    ts_created AS ts_visit_fup
  FROM
    datalake_ebdb_clean.visit_status_log
  WHERE
    ts_created::DATE >= '2025-01-01'
    AND event_type IN ('VISIT_DONE', 'VISIT_UNSUCCESSFUL')
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY id_visit_status_log DESC) = 1
),
bookings AS (
  SELECT
    b.id,
    b.id_house,
    COALESCE(b.visit_fup, fup_vsl.visit_fup) AS visit_fup,
    TO_DATE(b.ts_created) AS dt_booking,
    TO_DATE(CAST(b.dt_booking AS TIMESTAMP) + FLOOR((b.slot_day * 15 / 60)+8) * INTERVAL 1 HOURS + ABS(b.slot_day * 15 % 60) * INTERVAL 1 MINUTES) AS dt_visit_completed
  FROM
    datalake_ebdb_clean.booking AS b
  LEFT JOIN
    visit_fup_vsl AS fup_vsl
      ON b.id = fup_vsl.id_schedule
  WHERE
    b.business_context = 'SALE'
    AND b.ts_created IS NOT NULL
),
offers AS (
  SELECT
    id_offer,
    id_house,
    TO_DATE(ts_offer_submitted) AS dt_offer_submitted
  FROM
    datalake_sale_offer.sale_offer
),
events AS (
  SELECT
    dt_booking AS date,
    id_house,
    'VB' AS event_name,
    COUNT(DISTINCT id) AS event
  FROM
    bookings
  GROUP BY
    1, 2, 3
  UNION ALL
  SELECT
    dt_visit_completed AS date,
    id_house,
    'VC' AS event_name,
    COUNT(DISTINCT id) AS event
  FROM
    bookings
  WHERE
    visit_fup IN ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
    AND dt_visit_completed IS NOT NULL
  GROUP BY
    1, 2, 3
  UNION ALL
  SELECT
    dt_offer_submitted AS date,
    id_house,
    'OS' AS event_name,
    COUNT(DISTINCT id_offer)
  FROM
    offers
  GROUP BY
    1, 2, 3
  UNION ALL
  SELECT
    dt_offer_submitted AS date,
    id_house,
    'OA' AS event_name,
    COUNT(DISTINCT id_offer)
  FROM
    offers
  WHERE
    dt_offer_submitted IS NOT NULL
  GROUP BY
    1, 2, 3
),
aggregated_events AS (
  SELECT
    date,
    id_house,
    COALESCE(SUM(IF(event_name = 'VB', event, NULL)), 0) AS vbs,
    COALESCE(SUM(IF(event_name = 'VC', event, NULL)), 0) AS vcs,
    COALESCE(SUM(IF(event_name = 'OS', event, NULL)), 0) AS oss,
    COALESCE(SUM(IF(event_name = 'OA', event, NULL)), 0) AS oas
  FROM
    events
  GROUP BY
    1, 2
),
status_changes_aux AS (
  SELECT
    lbc.id_house,
    h.id_region,
    lbc.status,
    ure.ts_revision
  FROM
    datalake_ebdb_clean.listing_business_context_aud AS lbc
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON lbc.rev = ure.id
  JOIN
    datalake_ebdb_clean.house AS h
      ON lbc.id_house = h.id
  WHERE
    lbc.business_context = 'SALE'
  QUALIFY
    LAG(lbc.status) OVER (PARTITION BY lbc.id_house ORDER BY ure.ts_revision) IS DISTINCT FROM lbc.status
),
status_changes AS (
  SELECT
    id_house,
    id_region,
    status,
    ts_revision AS ts_status_started,
    LEAD(ts_revision) OVER (PARTITION BY id_house ORDER BY ts_revision) AS ts_status_ended
  FROM
    status_changes_aux
),
ongoing_listings AS (
  SELECT
    lbc.id_house,
    d.date,
    COALESCE(e.vbs, 0) AS vbs,
    COALESCE(e.vcs, 0) AS vcs,
    COALESCE(e.oas, 0) AS oas,
    COALESCE(e.oss, 0) AS oss,
    SUM(COALESCE(e.vbs, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 15 PRECEDING AND CURRENT ROW) as vbs_last_15_days,
    SUM(COALESCE(e.vbs, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) as vbs_last_30_days,
    SUM(COALESCE(e.vbs, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 60 PRECEDING AND CURRENT ROW) as vbs_last_60_days,
    SUM(COALESCE(e.vbs, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) as vbs_last_90_days,
    SUM(COALESCE(e.vcs, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 15 PRECEDING AND CURRENT ROW) as vcs_last_15_days,
    SUM(COALESCE(e.vcs, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) as vcs_last_30_days,
    SUM(COALESCE(e.vcs, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 60 PRECEDING AND CURRENT ROW) as vcs_last_60_days,
    SUM(COALESCE(e.vcs, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) as vcs_last_90_days,
    SUM(COALESCE(e.oss, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 15 PRECEDING AND CURRENT ROW) as oss_last_15_days,
    SUM(COALESCE(e.oss, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) as oss_last_30_days,
    SUM(COALESCE(e.oss, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 60 PRECEDING AND CURRENT ROW) as oss_last_60_days,
    SUM(COALESCE(e.oss, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) as oss_last_90_days,
    SUM(COALESCE(e.oas, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 15 PRECEDING AND CURRENT ROW) as oas_last_15_days,
    SUM(COALESCE(e.oas, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) as oas_last_30_days,
    SUM(COALESCE(e.oas, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 60 PRECEDING AND CURRENT ROW) as oas_last_60_days,
    SUM(COALESCE(e.oas, 0)) OVER (PARTITION BY lbc.id_house ORDER BY d.id_date ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) as oas_last_90_days
  FROM
    datalake_ebdb_clean.listing_business_context AS lbc
  JOIN
    datalake_quintoandar.aux_date AS d
      ON d.date BETWEEN TO_DATE(lbc.ts_first_publication) AND CURRENT_DATE
  LEFT JOIN
    aggregated_events AS e
      ON lbc.id_house = e.id_house
      AND d.date = e.date
  WHERE
    lbc.business_context = 'SALE'
    AND lbc.ts_first_publication IS NOT NULL
),
filtering_publisheds AS (
  SELECT
    ol.id_house,
    sc.id_region,
    ol.vbs_last_15_days,
    ol.vbs_last_30_days,
    ol.vbs_last_60_days,
    ol.vbs_last_90_days,
    ol.vcs_last_15_days,
    ol.vcs_last_30_days,
    ol.vcs_last_60_days,
    ol.vcs_last_90_days,
    ol.oss_last_15_days,
    ol.oss_last_30_days,
    ol.oss_last_60_days,
    ol.oss_last_90_days,
    ol.oas_last_15_days,
    ol.oas_last_30_days,
    ol.oas_last_60_days,
    ol.oas_last_90_days,
    IF(sc.status = 'PUBLISHED', ROW_NUMBER() OVER (PARTITION BY ol.id_house ORDER BY ol.date ASC), NULL) AS days_as_published,
    ol.date AS dt_published
  FROM
    ongoing_listings AS ol
  LEFT JOIN
    status_changes AS sc
      ON sc.id_house = ol.id_house
      AND ol.date BETWEEN sc.ts_status_started AND COALESCE(sc.ts_status_ended, CURRENT_TIMESTAMP)
  WHERE
    sc.status = 'PUBLISHED'
),
business_logic AS (
  SELECT
    id_house,
    id_region,
    vbs_last_15_days,
    vbs_last_30_days,
    vbs_last_60_days,
    vbs_last_90_days,
    vcs_last_15_days,
    vcs_last_30_days,
    vcs_last_60_days,
    vcs_last_90_days,
    oss_last_15_days,
    oss_last_30_days,
    oss_last_60_days,
    oss_last_90_days,
    oas_last_15_days,
    oas_last_30_days,
    oas_last_60_days,
    oas_last_90_days,
    CASE
      WHEN oas_last_15_days > 0 THEN 'OA'
      WHEN oss_last_15_days > 0 THEN 'OS'
      WHEN vcs_last_15_days > 0 THEN 'VC'
      WHEN vbs_last_15_days > 0 THEN 'VB'
      ELSE 'None'
    END AS highest_funnel_step_achieved_last_15_days,
    CASE
      WHEN oas_last_30_days > 0 THEN 'OA'
      WHEN oss_last_30_days > 0 THEN 'OS'
      WHEN vcs_last_30_days > 0 THEN 'VC'
      WHEN vbs_last_30_days > 0 THEN 'VB'
      ELSE 'None'
    END AS highest_funnel_step_achieved_last_30_days,
    CASE
      WHEN oas_last_60_days > 0 THEN 'OA'
      WHEN oss_last_60_days > 0 THEN 'OS'
      WHEN vcs_last_60_days > 0 THEN 'VC'
      WHEN vbs_last_60_days > 0 THEN 'VB'
      ELSE 'None'
    END AS highest_funnel_step_achieved_last_60_days,
    CASE
      WHEN oas_last_90_days > 0 THEN 'OA'
      WHEN oss_last_90_days > 0 THEN 'OS'
      WHEN vcs_last_90_days > 0 THEN 'VC'
      WHEN vbs_last_90_days > 0 THEN 'VB'
      ELSE 'None'
    END AS highest_funnel_step_achieved_last_90_days,
    CASE
      WHEN days_as_published > 90 THEN
        CASE
          WHEN vbs_last_15_days >= 3 THEN 'D5'
          WHEN vcs_last_15_days >= 2 THEN 'D5'
          WHEN oss_last_15_days >= 1 THEN 'D5'
          WHEN oas_last_15_days >= 1 THEN 'D5'
          WHEN vbs_last_15_days = 2 THEN 'D4'
          WHEN vbs_last_30_days >= 3 THEN 'D4'
          WHEN vcs_last_30_days >= 2 THEN 'D4'
          WHEN oss_last_30_days >= 1 THEN 'D4'
          WHEN oas_last_30_days >= 1 THEN 'D4'
          WHEN vbs_last_30_days = 2 THEN 'D3'
          WHEN vbs_last_60_days >= 3 THEN 'D3'
          WHEN vcs_last_60_days >= 2 THEN 'D3'
          WHEN oss_last_60_days >= 1 THEN 'D3'
          WHEN oas_last_60_days >= 1 THEN 'D3'
          WHEN vbs_last_60_days = 2 THEN 'D2'
          WHEN vbs_last_90_days >= 3 THEN 'D2'
          WHEN vcs_last_90_days >= 2 THEN 'D2'
          WHEN oss_last_90_days >= 1 THEN 'D2'
          WHEN oas_last_90_days >= 1 THEN 'D2'
          ELSE 'D1'
        END
      WHEN days_as_published <= 90 THEN
        CASE
          WHEN vbs_last_15_days >= 1 THEN 'D5'
          WHEN vcs_last_15_days >= 1 THEN 'D5'
          WHEN oss_last_15_days >= 1 THEN 'D5'
          WHEN oas_last_15_days >= 1 THEN 'D5'
          WHEN vcs_last_30_days >= 1 THEN 'D5'
          WHEN oss_last_30_days >= 1 THEN 'D5'
          WHEN oas_last_30_days >= 1 THEN 'D5'
          WHEN vbs_last_30_days >= 1 THEN 'D4'
          WHEN vcs_last_60_days >= 1 THEN 'D4'
          WHEN oss_last_60_days >= 1 THEN 'D4'
          WHEN oas_last_60_days >= 1 THEN 'D4'
          WHEN vbs_last_60_days >= 1 THEN 'D3'
          WHEN vcs_last_90_days >= 1 THEN 'D3'
          WHEN oss_last_90_days >= 1 THEN 'D3'
          WHEN oas_last_90_days >= 1 THEN 'D3'
          WHEN vbs_last_90_days >= 1 THEN 'D2'
          WHEN days_as_published <= 45 THEN 'D3'
          WHEN days_as_published > 45 THEN 'D2'
      END
    END AS tier,
    days_as_published,
    dt_published
  FROM
    filtering_publisheds
),
max_day_published_in_tier AS (
  SELECT
    id_house,
    id_region,
    highest_funnel_step_achieved_last_15_days,
    highest_funnel_step_achieved_last_30_days,
    highest_funnel_step_achieved_last_60_days,
    highest_funnel_step_achieved_last_90_days,
    vbs_last_15_days,
    vbs_last_30_days,
    vbs_last_60_days,
    vbs_last_90_days,
    vcs_last_15_days,
    vcs_last_30_days,
    vcs_last_60_days,
    vcs_last_90_days,
    oss_last_15_days,
    oss_last_30_days,
    oss_last_60_days,
    oss_last_90_days,
    oas_last_15_days,
    oas_last_30_days,
    oas_last_60_days,
    oas_last_90_days,
    days_as_published,
    MAX(days_as_published) OVER (PARTITION BY id_house, SUM(IF(LAG(tier) OVER (PARTITION BY id_house ORDER BY dt_published) IS DISTINCT FROM tier, 1, 0)) OVER (PARTITION BY id_house ORDER BY dt_published)) AS max_days_as_published,
    tier,
    dt_published
  FROM
    business_logic
),
creating_disclaimer AS (
  SELECT
    id_house,
    id_region,
    highest_funnel_step_achieved_last_15_days,
    highest_funnel_step_achieved_last_30_days,
    highest_funnel_step_achieved_last_60_days,
    highest_funnel_step_achieved_last_90_days,
    days_as_published AS days_as_published_at_start,
    max_days_as_published AS days_as_published_at_end,
    tier,
    CASE
      WHEN days_as_published > 90 AND vbs_last_15_days >= 3 THEN 'The listing has had at least 3 visits booked in the past 15 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vcs_last_15_days >= 2 THEN 'The listing has had at least 2 visits completed in the past 15 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND oss_last_15_days >= 1 THEN 'The listing has had at least 1 offer submitted in the past 15 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND oas_last_15_days >= 1 THEN 'The listing has had at least 1 offer accepted in the past 15 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vbs_last_15_days >= 2 THEN 'The listing has had at least 2 visits booked in the past 15 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vbs_last_30_days >= 3 THEN 'The listing has had at least 3 visits booked in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vcs_last_30_days >= 2 THEN 'The listing has had at least 2 visits completed in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND oss_last_30_days >= 1 THEN 'The listing has had at least 1 offer submitted in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND oas_last_30_days >= 1 THEN 'The listing has had at least 1 offer accepted in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vbs_last_60_days >= 3 THEN 'The listing has had at least 3 visits booked in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vcs_last_60_days >= 2 THEN 'The listing has had at least 2 visits completed in the past 60 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND oss_last_60_days >= 2 THEN 'The listing has had at least 2 offer submitted in the past 60 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND oas_last_60_days >= 1 THEN 'The listing has had at least 1 offer accepted in the past 60 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vbs_last_30_days >= 2 THEN 'The listing has had at least 2 visit booked in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vcs_last_90_days >= 3 THEN 'The listing has had at least 3 visit completed in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND oss_last_90_days >= 2 THEN 'The listing has had at least 2 offer submitted in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND oas_last_90_days >= 1 THEN 'The listing has had at least 1 offer accepted in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vbs_last_90_days >= 1 THEN 'The listing has had at least 1 visit booked in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published > 90 AND vbs_last_60_days >= 2 THEN 'The listing has had at least 2 visit booked in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND vbs_last_15_days >= 1 THEN 'The new listing has had at least 1 visit booked in the past 15 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND vcs_last_15_days >= 1 THEN 'The new listing has had at least 1 visit completed in the past 15 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND oss_last_15_days >= 1 THEN 'The new listing has had at least 1 offer submitted in the past 15 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND oas_last_15_days >= 1 THEN 'The new listing has had at least 1 offer accepted in the past 15 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND vbs_last_30_days >= 1 THEN 'The new listing has had at least 1 visit booked in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND vcs_last_30_days >= 1 THEN 'The new listing has had at least 1 visit completed in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND oss_last_30_days >= 1 THEN 'The new listing has had at least 1 offer submitted in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND oas_last_30_days >= 1 THEN 'The new listing has had at least 1 offer accepted in the past 30 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND vbs_last_60_days >= 1 THEN 'The new listing has had at least 1 visit booked in the past 60 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND vcs_last_60_days >= 1 THEN 'The new listing has had at least 1 visit completed in the past 60 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND oss_last_60_days >= 1 THEN 'The new listing has had at least 1 offer submitted in the past 60 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND oas_last_60_days >= 1 THEN 'The new listing has had at least 1 visit booked in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND vbs_last_90_days >= 1 THEN 'The new listing has had at least 1 visit booked in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND vcs_last_90_days >= 1 THEN 'The new listing has had at least 1 visit completed in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND oss_last_90_days >= 1 THEN 'The new listing has had at least 1 offer submitted in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 90 AND oas_last_90_days >= 1 THEN 'The new listing has had at least 1 offer accepted in the past 90 days and has been listed for ' || max_days_as_published || ' days.'
      WHEN days_as_published <= 45 THEN 'The new listing has not received any demand event and has been listed for at least 45 days.'
      WHEN days_as_published > 45 THEN 'The listing has not received any demand event and has been listed for more than 45 days.'
      ELSE 'The listing has not received any demand event and has been listed for more than ' || max_days_as_published || ' days.'
    END AS tier_disclaimer,
    dt_published AS ts_tier_started
  FROM
    max_day_published_in_tier
),
grouping_tiers AS (
  SELECT
    id_house,
    id_region,
    highest_funnel_step_achieved_last_15_days,
    highest_funnel_step_achieved_last_30_days,
    highest_funnel_step_achieved_last_60_days,
    highest_funnel_step_achieved_last_90_days,
    days_as_published_at_start,
    days_as_published_at_end,
    tier,
    tier_disclaimer,
    ts_tier_started
  FROM
    creating_disclaimer
  QUALIFY
    ts_tier_started = MIN(ts_tier_started) OVER (PARTITION BY id_house)
    OR tier != LAG(tier) OVER (PARTITION BY id_house ORDER BY ts_tier_started)
)
SELECT
  id_house,
  id_region,
  highest_funnel_step_achieved_last_15_days,
  highest_funnel_step_achieved_last_30_days,
  highest_funnel_step_achieved_last_60_days,
  highest_funnel_step_achieved_last_90_days,
  days_as_published_at_start,
  days_as_published_at_end,
  tier,
  CASE
    WHEN tier = 'D5' THEN 'High Demand'
    WHEN tier = 'D4' THEN 'Good Demand'
    WHEN tier = 'D3' THEN 'Some Demand'
    WHEN tier = 'D2' THEN 'Low Demand'
    WHEN tier = 'D1' THEN 'No Demand'
  END AS tier_name,
  tier_disclaimer,
  ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_tier_started DESC) = 1 AS is_last_tier,
  ts_tier_started,
  DATE_SUB(LEAD(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started), 1) AS ts_tier_ended
FROM
  grouping_tiers
