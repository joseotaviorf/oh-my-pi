WITH extra_debug AS (
  SELECT
    d.*
  FROM datalake_amplitude_clean.170698_visit_schedule_confirmed_events AS v
  RIGHT JOIN datalake_amplitude_clean.170698_debug_visit_schedule_confirmed_events AS d
    ON v.ep_visit_code = d.ep_visit_code AND v.id_user = d.id_user
  WHERE
    v.ep_visit_code IS NULL
), cross_platform AS (
  SELECT
    '170698' AS id_app,
    id_user,
    country AS user_country,
    user_properties,
    ts_event,
    up_platform AS app_type,
    ep_visit_code AS id_visit,
    up_utm_source AS utm_source,
    up_utm_medium AS utm_medium,
    up_utm_campaign AS utm_campaign,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    up_entrance_uri AS entrance_uri,
    up_adjust_network AS adjust_network,
    COALESCE(
      NULLIF(
        CASE
          WHEN up_platform IN ('web_desktop', 'web_mobile')
          THEN up_utm_source
          ELSE up_adjust_network
        END,
        'Organic'
      ),
      'organic'
    ) AS media_source
  FROM datalake_amplitude_clean.170698_visit_schedule_confirmed_events
  WHERE
    NOT ep_visit_code IS NULL
  UNION ALL
  SELECT
    '170698' AS id_app,
    id_user,
    country AS user_country,
    user_properties,
    ts_event,
    up_platform AS app_type,
    ep_visit_code AS id_visit,
    up_utm_source AS utm_source,
    up_utm_medium AS utm_medium,
    up_utm_campaign AS utm_campaign,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    up_entrance_uri AS entrance_uri,
    up_adjust_network AS adjust_network,
    COALESCE(
      NULLIF(
        CASE
          WHEN up_platform IN ('web_desktop', 'web_mobile')
          THEN up_utm_source
          ELSE up_adjust_network
        END,
        'Organic'
      ),
      'organic'
    ) AS media_source
  FROM extra_debug
  WHERE
    NOT ep_visit_code IS NULL
)
SELECT
  id_app,
  id_visit,
  country_code,
  user_country,
  app_type,
  media_source,
  adjust_network,
  utm_source,
  utm_campaign,
  utm_medium,
  utm_content,
  utm_term,
  entrance_uri,
  is_branded,
  branded,
  ts_event
FROM (
  SELECT
    id_app,
    id_visit,
    GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    user_country,
    app_type,
    COALESCE(media_source, 'Unknown') AS media_source,
    adjust_network,
    utm_source,
    utm_campaign,
    utm_medium,
    utm_content,
    utm_term,
    entrance_uri,
    COALESCE(
      (
        (
          UPPER(utm_campaign) LIKE '%BRANDED%'
          OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%'
        )
        AND NOT LOWER(utm_campaign) LIKE '%non-branded%'
      ),
      FALSE
    ) AS is_branded,
    CASE
      WHEN (
        UPPER(utm_campaign) LIKE '%BRANDED%'
        OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%'
      )
      AND NOT LOWER(utm_campaign) LIKE '%non-branded%'
      THEN 'Branded'
      ELSE 'Outro'
    END AS branded, /* temporary column to join with taxonomy, */ /* it can be replaced by the usage of previous column but */ /* some refactoring will be needed in demand taxonomy */
    ts_event,
    ROW_NUMBER() OVER (PARTITION BY id_visit ORDER BY ts_event DESC) AS _w
  FROM cross_platform
) AS _t
WHERE
  _w = 1