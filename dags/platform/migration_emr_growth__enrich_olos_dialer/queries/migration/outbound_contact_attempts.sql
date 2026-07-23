WITH users_last_register AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_agent ORDER BY CAST(year || '-' || month || '-' || day AS DATE) DESC) AS _w
    FROM datalake_olos_dialer_clean.users
  ) AS _t
  WHERE
    _w = 1
), campaign_last_register AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_campaign ORDER BY CAST(year || '-' || month || '-' || day AS DATE) DESC) AS _w
    FROM datalake_olos_dialer_clean.campaign
  ) AS _t
  WHERE
    _w = 1
), disposition_last_register AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_disposition ORDER BY CAST(year || '-' || month || '-' || day AS DATE) DESC) AS _w
    FROM datalake_olos_dialer_clean.disposition
  ) AS _t
  WHERE
    _w = 1
), info_campaign_type_last_register AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_campaign_type ORDER BY CAST(year || '-' || month || '-' || day AS DATE) DESC) AS _w
    FROM datalake_olos_dialer_clean.info_campaign_type
  ) AS _t
  WHERE
    _w = 1
), campaign_customer_last_register AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_campaign, id_customer ORDER BY CAST(year || '-' || month || '-' || day AS DATE) DESC) AS _w
    FROM datalake_olos_dialer_clean.campaign_customer
  ) AS _t
  WHERE
    _w = 1
), customer_last_register AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_customer ORDER BY CAST(year || '-' || month || '-' || day AS DATE) DESC) AS _w
    FROM datalake_olos_dialer_clean.customer
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  outbound.id_call AS id_call,
  outbound.id_lead AS id_lead,
  users.user_name AS agent_user_name,
  users.email AS agent_email,
  users.agent_profile AS agent_profile,
  REPLACE(SPLIT(campaign.description, '_')[0], '5ANDAR', 'QUINTO_ANDAR_OUTBOUND') AS sales_company,
  campaign.description AS campaign_name,
  info_campaign_type.description AS campaign_type,
  disposition.description AS olos_disposition,
  phone_output_olos_wololo_mapping.wololo_disposition_description AS wololo_disposition,
  outbound.original_phone_number AS phone_number,
  outbound.dnis AS dnis,
  CASE
    WHEN outbound.id_phone_type = 1
    THEN 'Residential Fixed Phone'
    WHEN outbound.id_phone_type = 2
    THEN 'Business Fixed Phone'
    WHEN outbound.id_phone_type = 3
    THEN 'Personal Mobile Phone'
    WHEN outbound.id_phone_type = 4
    THEN 'Business Mobile Phone'
    WHEN outbound.id_phone_type = 9
    THEN 'Generic Phone'
    WHEN outbound.id_phone_type = 65536
    THEN 'MsBot'
  END AS phone_type,
  customer.name AS organization,
  TIMESTAMPDIFF(SECOND, TO_DATE(outbound.ts_started), TO_DATE(outbound.ts_call_ended)) AS duration_in_seconds,
  outbound.ts_started AS ts_call_started,
  outbound.ts_call_ended AS ts_call_ended,
  outbound.year AS year,
  outbound.month AS month,
  outbound.day AS day
FROM datalake_olos_dialer_clean.attempts_raw_data AS outbound
LEFT JOIN users_last_register AS users
  ON users.id_agent = outbound.id_agent
LEFT JOIN campaign_last_register AS campaign
  ON campaign.id_campaign = outbound.id_campaign
LEFT JOIN info_campaign_type_last_register AS info_campaign_type
  ON info_campaign_type.id_campaign_type = campaign.id_campaign_type
LEFT JOIN disposition_last_register AS disposition
  ON disposition.id_disposition = outbound.id_disposition
LEFT JOIN datalake_olos_dialer.phone_output_olos_wololo_mapping
  ON phone_output_olos_wololo_mapping.id_wololo_disposition = disposition.id_disposition
LEFT JOIN campaign_customer_last_register AS campaign_customer
  ON campaign_customer.id_campaign = outbound.id_campaign
LEFT JOIN customer_last_register AS customer
  ON customer.id_customer = campaign_customer.id_customer
WHERE
  MAKE_DATE(outbound.year, outbound.month, outbound.day) BETWEEN DATE_ADD(CAST('{load_start_date}' AS DATE), STRUCT(days_past AS days_past) * -1) AND CAST('{load_end_date}' AS DATE)
  AND customer.name = 'Inside Sales'