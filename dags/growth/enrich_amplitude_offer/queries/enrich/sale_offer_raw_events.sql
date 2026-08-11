SELECT
  id_user,
  id_app,
  id_house,
  id_offer,
  app_type,
  utm_source,
  utm_medium,
  utm_campaign,
  utm_content,
  utm_term,
  entrance_uri,
  branded,
  is_branded,
  ts_event,
  year,
  month,
  day
FROM (
  SELECT
    id_user,
    '170698' AS id_app,
    ep_id_house AS id_house,
    ep_id_firestore AS id_offer,
    up_app_type AS app_type,
    up_utm_source AS utm_source,
    up_utm_medium AS utm_medium,
    up_utm_campaign AS utm_campaign,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    up_entrance_uri AS entrance_uri,
    CASE
      WHEN (
        UPPER(up_utm_campaign) LIKE '%BRANDED%'
        OR UPPER(up_utm_campaign) LIKE '%INSTITUCIONAL%'
      )
      AND NOT UPPER(up_utm_campaign) LIKE '%NON-BRANDED%'
      THEN 'Branded'
      ELSE 'Outro'
    END AS branded,
    COALESCE(
      (
        (
          UPPER(up_utm_campaign) LIKE '%BRANDED%'
          OR UPPER(up_utm_campaign) LIKE '%INSTITUCIONAL%'
        )
        AND NOT LOWER(up_utm_campaign) LIKE '%non-branded%'
      ),
      FALSE
    ) AS is_branded,
    ts_event,
    year,
    month,
    day,
    ROW_NUMBER() OVER (PARTITION BY ep_id_firestore ORDER BY ts_event DESC) AS _w,
    ep_id_firestore
  FROM datalake_amplitude_clean.170698_sale_offer_form_accepted_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
