WITH app_205027_referral_form_events AS (
  SELECT
    CAST(id_lead AS BIGINT) AS id_lead,
    id_device,
    1 AS rule_num,
    'referral' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, country) AS country_code,
    ts_event,
    utm_campaign,
    utm_medium,
    utm_source,
    utm_content,
    utm_term,
    app_type AS platform,
    referring_domain,
    region,
    city,
    uuid
  FROM datalake_amplitude_clean.205027_referral_form_accepted_events
  WHERE
    NOT CAST(id_lead AS INT) IS NULL
    AND year >= YEAR(TO_DATE(CURRENT_DATE - INTERVAL '2' YEAR))
  UNION
  SELECT
    CAST(id_lead AS BIGINT) AS id_lead,
    id_device,
    1 AS rule_num,
    'referral' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, country) AS country_code,
    ts_event,
    utm_campaign,
    utm_medium,
    utm_source,
    utm_content,
    utm_term,
    app_type AS platform,
    referring_domain,
    region,
    city,
    uuid
  FROM datalake_amplitude_clean.205027_referral_form_discarded_events
  WHERE
    NOT CAST(id_lead AS INT) IS NULL
    AND year >= YEAR(TO_DATE(CURRENT_DATE - INTERVAL '2' YEAR))
), app_183047_form_submitted_events AS (
  SELECT
    id_lead_ebdb AS id_lead,
    id_device,
    4 AS rule_num,
    'formfield' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, country) AS country_code,
    ts_event,
    utm_campaign,
    utm_medium,
    utm_source,
    utm_content,
    utm_term,
    app_type AS platform,
    referring_domain,
    region,
    city,
    uuid
  FROM datalake_amplitude_clean.183047_lead_form_submitted_events
  WHERE
    NOT id_lead_ebdb IS NULL
    AND year >= YEAR(TO_DATE(CURRENT_DATE - INTERVAL '2' YEAR))
  UNION
  SELECT
    id_lead_ebdb AS id_lead,
    id_device,
    4 AS rule_num,
    'formfield' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, country) AS country_code,
    ts_event,
    utm_campaign,
    utm_medium,
    utm_source,
    utm_content,
    utm_term,
    app_type AS platform,
    referring_domain,
    region,
    city,
    uuid
  FROM datalake_amplitude_clean.183047_price_suggestion_form_submitted_events
  WHERE
    NOT id_lead_ebdb IS NULL
    AND year >= YEAR(TO_DATE(CURRENT_DATE - INTERVAL '2' YEAR))
  UNION
  SELECT
    id_lead_ebdb AS id_lead,
    id_device,
    4 AS rule_num,
    'formfield' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, country) AS country_code,
    ts_event,
    utm_campaign,
    utm_medium,
    utm_source,
    utm_content,
    utm_term,
    app_type AS platform,
    referring_domain,
    region,
    city,
    uuid
  FROM datalake_amplitude_clean.183047_price_suggestion_sale_form_submitted_events
  WHERE
    NOT id_lead_ebdb IS NULL
    AND year >= YEAR(TO_DATE(CURRENT_DATE - INTERVAL '2' YEAR))
), app_183047_intro_page_viewed_events AS (
  SELECT
    CAST(GET_JSON_OBJECT(event_properties, lead_id) AS BIGINT) AS id_lead,
    id_device,
    5 AS rule_num,
    'opr' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, country) AS country_code,
    ts_event,
    up_utm_campaign AS utm_campaign,
    up_utm_medium AS utm_medium,
    up_utm_source AS utm_source,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    CAST(GET_JSON_OBJECT(user_properties, platform) AS STRING) AS platform,
    CAST(GET_JSON_OBJECT(user_properties, referring_domain) AS STRING) AS referring_domain,
    region,
    city,
    uuid
  FROM datalake_amplitude_clean.183047_intro_page_viewed_events
  WHERE
    NOT GET_JSON_OBJECT(event_properties, lead_id) IS NULL
    AND year >= YEAR(TO_DATE(CURRENT_DATE - INTERVAL '2' YEAR))
), app_183047_property_details_page_viewed_events AS (
  SELECT
    CAST(GET_JSON_OBJECT(event_properties, '$.lead_id') AS BIGINT) AS id_lead,
    id_device,
    6 AS rule_num,
    'opr' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    ts_event,
    up_utm_campaign AS utm_campaign,
    up_utm_medium AS utm_medium,
    up_utm_source AS utm_source,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    CAST(GET_JSON_OBJECT(user_properties, '$.platform') AS STRING) AS platform,
    CAST(GET_JSON_OBJECT(user_properties, '$.referring_domain') AS STRING) AS referring_domain,
    region,
    city,
    uuid
  FROM datalake_amplitude_clean.183047_property_details_page_viewed_events
  WHERE
    NOT GET_JSON_OBJECT(event_properties, '$.lead_id') IS NULL
    AND year >= YEAR(TO_DATE(CURRENT_DATE - INTERVAL '2' YEAR))
), app_183047_rent_pricing_new_listing_form_submitted_events AS (
  SELECT
    CAST(GET_JSON_OBJECT(event_properties, '$.lead_id') AS BIGINT) AS id_lead,
    id_device,
    7 AS rule_num,
    'opr' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    ts_event,
    up_utm_campaign AS utm_campaign,
    up_utm_medium AS utm_medium,
    up_utm_source AS utm_source,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    CAST(GET_JSON_OBJECT(user_properties, '$.platform') AS STRING) AS platform,
    CAST(GET_JSON_OBJECT(user_properties, '$.referring_domain') AS STRING) AS referring_domain,
    region,
    city,
    uuid
  FROM datalake_amplitude_clean.183047_rent_pricing_new_listing_form_submitted_events
  WHERE
    NOT GET_JSON_OBJECT(event_properties, '$.lead_id') IS NULL
    AND year >= YEAR(TO_DATE(CURRENT_DATE - INTERVAL '2' YEAR))
), app_183047_rent_pricing_new_listing_page_viewed_events AS (
  SELECT
    CAST(GET_JSON_OBJECT(event_properties, '$.lead_id') AS BIGINT) AS id_lead,
    id_device,
    8 AS rule_num,
    'opr' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    ts_event,
    up_utm_campaign AS utm_campaign,
    up_utm_medium AS utm_medium,
    up_utm_source AS utm_source,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    CAST(GET_JSON_OBJECT(user_properties, '$.platform') AS STRING) AS platform,
    CAST(GET_JSON_OBJECT(user_properties, '$.referring_domain') AS STRING) AS referring_domain,
    region,
    city,
    uuid
  FROM datalake_amplitude_clean.183047_rent_pricing_new_listing_page_viewed_events
  WHERE
    NOT GET_JSON_OBJECT(event_properties, '$.lead_id') IS NULL
    AND year >= YEAR(TO_DATE(CURRENT_DATE - INTERVAL '2' YEAR))
), lead_events_union AS (
  SELECT
    *,
    RANK() OVER (PARTITION BY id_lead ORDER BY ts_event) AS rn
  FROM app_205027_referral_form_events
  UNION
  SELECT
    *,
    RANK() OVER (PARTITION BY id_lead ORDER BY ts_event DESC) AS rn
  FROM app_183047_form_submitted_events
  UNION
  SELECT
    *,
    RANK() OVER (PARTITION BY id_lead ORDER BY ts_event DESC) AS rn
  FROM app_183047_intro_page_viewed_events
  UNION
  SELECT
    *,
    RANK() OVER (PARTITION BY id_lead ORDER BY ts_event DESC) AS rn
  FROM app_183047_property_details_page_viewed_events
  UNION
  SELECT
    *,
    RANK() OVER (PARTITION BY id_lead ORDER BY ts_event DESC) AS rn
  FROM app_183047_rent_pricing_new_listing_form_submitted_events
  UNION
  SELECT
    *,
    RANK() OVER (PARTITION BY id_lead ORDER BY ts_event DESC) AS rn
  FROM app_183047_rent_pricing_new_listing_page_viewed_events
)
SELECT
  id_lead,
  COALESCE(uuid, '') AS uuid,
  id_device,
  country_code,
  user_country,
  rule_num,
  COALESCE(platform, '') AS platform,
  COALESCE(referring_domain, '') AS referring_domain,
  COALESCE(region, '') AS region,
  COALESCE(city, '') AS city,
  SUBSTRING(COALESCE(utm_campaign, ''), 1, 250) AS utm_campaign,
  SUBSTRING(COALESCE(utm_medium, ''), 1, 250) AS utm_medium,
  SUBSTRING(COALESCE(utm_source, ''), 1, 250) AS utm_source,
  SUBSTRING(COALESCE(utm_content, ''), 1, 250) AS utm_content,
  SUBSTRING(COALESCE(utm_term, ''), 1, 250) AS utm_term,
  ts_event
FROM lead_events_union
WHERE
  rn = 1
