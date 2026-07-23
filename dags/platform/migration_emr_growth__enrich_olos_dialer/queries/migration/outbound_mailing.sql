WITH campaign_last_register AS (
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
  mailing.id_lead,
  campaign.description AS campaign_name,
  customer.name AS organization,
  REPLACE(SPLIT(campaign.description, '_')[0], '5ANDAR', 'QUINTO_ANDAR_OUTBOUND') AS sales_company,
  mailing.phone1,
  mailing.phone2,
  mailing.phone3,
  mailing.ts_created,
  mailing.ts_imported,
  mailing.year,
  mailing.month,
  mailing.day
FROM datalake_olos_dialer_clean.mailing
LEFT JOIN campaign_last_register AS campaign
  ON campaign.id_campaign = mailing.id_campaign
LEFT JOIN campaign_customer_last_register AS campaign_customer
  ON campaign_customer.id_campaign = mailing.id_campaign
LEFT JOIN customer_last_register AS customer
  ON customer.id_customer = campaign_customer.id_customer
WHERE
  MAKE_DATE(mailing.year, mailing.month, mailing.day) BETWEEN DATE_ADD(CAST('{load_start_date}' AS DATE), STRUCT(days_past AS days_past) * -1) AND CAST('{load_end_date}' AS DATE)
  AND (
    customer.name IN ('Inside Sales', 'AL Inside Sales', 'AeC Inside Sales', 'Atento Inside Sales', 'Inside Sales', 'QA Inside Sales')
    OR customer.name IS NULL
  )