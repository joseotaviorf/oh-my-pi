WITH
contract_docusign_signed_conversions AS (
    SELECT
        csa.ts_event,
        csa.id_amplitude,
        csa.id_session,
        csa.id_house,
        csa.utm_source,
        csa.utm_medium,
        csa.utm_campaign,
        csa.utm_content,
        csa.utm_term,
        clofhl.sk_region
    FROM
      datalake_amplitude_page_viewed_events.contract_docusign_signed_events csa
      LEFT JOIN dw_rent.fact_house_listings clofhl
        ON CAST(csa.id_house AS INTEGER) = CAST(clofhl.sk_house_listing AS BIGINT) / 1000
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
contract_docusign_signed_sessions AS (
  SELECT
    csc.id_amplitude,
    csc.id_session,
    csc.id_house,
    csc.utm_source,
    csc.utm_medium,
    csc.utm_campaign,
    csc.utm_content,
    csc.utm_term,
    MIN(csc.ts_event) AS ts_event
  FROM
    contract_docusign_signed_conversions csc
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),
pre_events AS (
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM
      datalake_amplitude_page_viewed_events.listing_page_viewed
    UNION ALL
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM
      datalake_amplitude_page_viewed_events.home_page_viewed
    UNION ALL
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM
      datalake_amplitude_page_viewed_events.search_results_page_viewed
    UNION ALL
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM
      datalake_amplitude_page_viewed_events.schedule_page_viewed
    UNION ALL
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM
      contract_docusign_signed_sessions
),
first_event_on_session AS (
  SELECT
    min(ts_event) AS ts_event,
    id_amplitude,
    id_session
  FROM
    pre_events
  GROUP BY 2,3
),
events AS (
  SELECT
    p.*
  FROM
    pre_events p
    JOIN first_event_on_session r
      ON p.ts_event = r.ts_event
      AND p.id_amplitude = r.id_amplitude
      AND p.id_session = r.id_session
),
conversion_sessions_unique AS (
  -- retrieve conversion sessions, indicating last conversion session
  SELECT
    css.id_session,
    css.id_amplitude,
    er.ts_event AS ts_session,
    nullif(lag(er.ts_event) over (partition BY css.id_amplitude ORDER BY er.ts_event), er.ts_event) AS ts_last_session
  FROM
    contract_docusign_signed_sessions css
    JOIN first_event_on_session er
      ON er.id_amplitude = css.id_amplitude
      AND er.id_session = css.id_session
    GROUP BY 1, 2, 3
),
conversion_events AS (
  -- retrieve conversion events together with their session info
  SELECT
    csc.ts_event,
    csc.id_session,
    csc.id_amplitude,
    csc.sk_region,
    csu.ts_session,
    csu.ts_last_session,
    RANK() OVER (PARTITION BY csc.id_amplitude ORDER BY csc.ts_event) AS rnk_conversion
  FROM
    contract_docusign_signed_conversions csc
  JOIN
    conversion_sessions_unique csu
    ON csu.id_amplitude = csc.id_amplitude
    AND csu.id_session = csc.id_session
),
touchpoints AS (
  -- aggregate events to attributed sessions (=touchpoints)
  -- determine for each session the start_time AND the time of closest conversion event
  -- ORDER matters for building seq. paths - user ASC > Nst conversion ASC > Nst session_start ASC
  SELECT
    -- Collect the coalesced id
    evt.id_amplitude,
    evt.id_session,
    evt.utm_source || '/' || evt.utm_medium || '/' ||
    (CASE
      WHEN evt.utm_campaign LIKE '%branded%' AND LOWER(evt.utm_campaign) NOT LIKE '%non-branded%' THEN 'true'
      WHEN evt.utm_campaign LIKE '%institucional%' THEN 'true'
      ELSE 'false'
    END) AS utm_source_medium_branded,
    evt.ts_event AS session_start_time,
    conv.sk_region,
    conv.ts_event AS conversion_time,
    conv.rnk_conversion AS nst_conversion
  FROM
    conversion_events conv
  LEFT JOIN events evt
  	ON evt.id_amplitude = conv.id_amplitude
  	AND evt.ts_event > COALESCE(conv.ts_last_session, DATE('2000-01-01')) -- JOIN events that happened between last conversion AND current conversion
    AND evt.ts_event <= conv.ts_session
  GROUP BY 1,2,3,4,5,6,7
)
-- aggregate touchpoints to unique conversions with their path concatenated in one column
SELECT
  CAST(date_format(DATE(conversion_time), 'yyyyMMdd')::INT AS STRING) AS sk_conversion_date,
  CAST(sk_region AS STRING),
  -- Using the coalesced id
  CAST(CAST(id_amplitude * 1000 + nst_conversion AS BIGINT) AS STRING) AS unique_conversion_id,
  CAST(ARRAY_JOIN(collect_list(utm_source_medium_branded), '; ') AS VARCHAR(20000)) AS path_utm_source_medium_branded,
  NOW()::STRING AS ts_load
FROM
  touchpoints
WHERE
  conversion_time >= CURRENT_DATE - INTERVAL '3' MONTH
  -- Athena removes float part. Added cast to INT to keep retrocompatibility in migration
  AND MONTHS_BETWEEN(conversion_time, session_start_time)::INT <= 6
GROUP BY 1, 2,3
