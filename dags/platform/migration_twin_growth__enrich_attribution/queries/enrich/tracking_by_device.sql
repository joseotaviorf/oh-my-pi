WITH tracking AS (
  SELECT
    id_anonymous AS id_device,
    user_properties:egw_referrer_domain AS referrer_domain,
    user_properties:egw_referrer_entrance_uri AS entrance_uri,
    egw_last_attribution_time AS ts_utm_attribution,
    from_unixtime(user_properties:egw_referrer_ts / 1000) AS ts_referral_attribution,

    -- UTM Medium
    CASE
      WHEN ts_utm_attribution >= ts_referral_attribution THEN egw_utm_medium
      WHEN ts_referral_attribution IS NULL THEN egw_utm_medium
      WHEN referrer_domain LIKE ANY ('%google%', '%bing%', '%yahoo%') THEN 'seo'
      WHEN referrer_domain LIKE ANY ('%chatgpt.%', '%gemini.%', '%copilot.%', '%perplexity.%') THEN 'llm'
      WHEN referrer_domain LIKE ANY ('%claude.%', '%you.com%', '%poe.com%', '%deepseek.%') THEN 'other_llm'
    END AS utm_medium,

    -- UTM Source
    CASE
      WHEN utm_medium = 'seo' AND referrer_domain LIKE '%google%' THEN 'google'
      WHEN utm_medium = 'seo' AND referrer_domain LIKE '%bing%' THEN 'bing'
      WHEN utm_medium = 'seo' AND referrer_domain LIKE '%yahoo%' THEN 'yahoo'
      WHEN utm_medium = 'llm' AND referrer_domain LIKE '%chatgpt.%' THEN 'chatgpt'
      WHEN utm_medium = 'llm' AND referrer_domain LIKE '%gemini.%' THEN 'gemini'
      WHEN utm_medium = 'llm' AND referrer_domain LIKE '%copilot.%' THEN 'copilot'
      WHEN utm_medium = 'llm' AND referrer_domain LIKE '%perplexity.%' THEN 'perplexity'
      WHEN utm_medium = 'other_llm' THEN 'other_llm'
      ELSE egw_utm_source
    END AS utm_source,

    -- UTM Campaign
    CASE
      WHEN utm_medium = 'seo' AND entrance_uri IN ('https://www.quintoandar.com.br/', 'https://www.quintoandar.com.br') THEN 'branded'
      WHEN utm_medium = 'seo' THEN 'non-branded'
      WHEN utm_medium IN ('llm', 'other_llm') THEN 'llm'
      ELSE egw_utm_campaign
    END AS utm_campaign,

    -- UTM Content
    CASE
      WHEN utm_medium = 'seo' THEN NULL
      WHEN utm_medium IN ('llm', 'other_llm') THEN NULL
      ELSE egw_utm_content
    END AS utm_content,

    -- UTM Term
    CASE
      WHEN utm_medium = 'seo' THEN NULL
      WHEN utm_medium IN ('llm', 'other_llm') THEN NULL
      ELSE egw_utm_term
    END AS utm_term,

    MD5(
      CONCAT(
        COALESCE(utm_source, 'utm_source'),
        COALESCE(utm_medium, 'utm_medium'),
        COALESCE(utm_campaign, 'utm_campaign'),
        COALESCE(utm_content, 'utm_content'),
        COALESCE(utm_term, 'utm_term')
      )
    ) AS utm_hash,

    ts_event AS ts_tracking
  FROM
    datalake_cdp_clean.user_tracking
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
tracking_by_device_union AS (
  SELECT
    id_device,
    utm_medium,
    utm_source,
    utm_campaign,
    utm_content,
    utm_term,
    utm_hash,
    ts_tracking
  FROM tracking
  WHERE id_device IS NOT NULL

  UNION

  /*
  Union with the last row per device from the existing tracking_by_device table so that
  the LAG-based group detection (below) can tell whether the first event in this batch
  continues the same UTM group or starts a new one.
  Example
  All events for a **single** device. As the logic partitions by device, events from
  one device won't affect the group detection for another device.
  Batch 1 produces:
    utm_hash  ts_start  ts_end
    a         1         2
  Batch 2 arrives with events:
    utm_hash  ts
    a         3
    b         4
    a         5
    a         6
  Without the union, tracking_by_device after batch 2:
    utm_hash  ts_start  ts_end
    a         1         2       ← batch 1 row, never updated
    a         3         3       ← this session should be merged into the batch 1 row
    b         4         4
    a         5         6
  With the union, tracking_by_device after batch 2:
    utm_hash  ts_start  ts_end
    a         1         3       ← batch 1 row correctly extended
    b         4         4
    a         5         6
    */
  SELECT
    id_device,
    utm_medium,
    utm_source,
    utm_campaign,
    utm_content,
    utm_term,
    utm_hash,
    ts_utm_attribution_start AS ts_tracking
  FROM datalake_attribution.tracking_by_device
  WHERE id_device IN (SELECT DISTINCT id_device FROM tracking)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_device ORDER BY ts_utm_attribution_start DESC) = 1
),
groups_identification AS (
  SELECT
    *,
    CASE
      WHEN LAG(utm_hash) OVER (PARTITION BY id_device ORDER BY ts_tracking ASC) = utm_hash THEN 0
      ELSE 1
    END AS is_new_group
  FROM tracking_by_device_union
),
groups AS (
  SELECT
    *,
    SUM(is_new_group) OVER (PARTITION BY id_device ORDER BY ts_tracking ASC) AS group_id
  FROM groups_identification
)
SELECT
  id_device,
  utm_source,
  utm_medium,
  utm_campaign,
  utm_content,
  utm_term,
  utm_hash,
  MIN(ts_tracking) AS ts_utm_attribution_start,
  MAX(ts_tracking) AS ts_utm_attribution_end
FROM groups
GROUP BY id_device, utm_source, utm_medium, utm_campaign, utm_content, utm_term, utm_hash, group_id
