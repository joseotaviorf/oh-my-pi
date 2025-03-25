WITH distinct_supply_recurrence AS (
    SELECT  
        sk_company,
        id_by_real_estate,
        id_offer,
        LEFT(business_context, 4) AS business_context,
        dt_listing_created
    FROM
        datalake_growth_lab_clean.supply_recurrence
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY sk_company, id_by_real_estate, business_context ORDER BY dt_listing_created) = 1
),
joined_with_supply_processor AS (
    SELECT
        l.id,
        sr.id_offer AS id_offer_zap,
        sr.business_context,
        sr.dt_listing_created AS dt_crawler,
        DATE(IF(sr.business_context = 'SALE', l.ts_first_sale_version_created_by_company, l.ts_first_rent_version_created_by_company)) AS dt_supply_processor
    FROM
        distinct_supply_recurrence AS sr
    JOIN
        datalake_company.company_sks AS cs
            ON sr.sk_company = cs.sk_company
    JOIN
        datalake_brokers_supply_processor.lead_3p AS l
            ON cs.uuid_company = l.uuid_company
            AND sr.id_by_real_estate = l.id_by_real_estate
),
joined_with_difference AS (
  SELECT
      id AS id_lead_3p,
      id_offer_zap,
      business_context,
      DATEDIFF(dt_supply_processor, dt_crawler) AS days_crawler_to_supply_processor,
      dt_crawler,
      dt_supply_processor
  FROM
      joined_with_supply_processor
)
SELECT
    id_lead_3p,
    id_offer_zap,
    business_context,
    CASE
        WHEN days_crawler_to_supply_processor IS NULL THEN 'N/A'
        WHEN days_crawler_to_supply_processor < -14 THEN '< -14'
        WHEN days_crawler_to_supply_processor < 0 THEN 'EARLY_FRESH'
        WHEN days_crawler_to_supply_processor <= 14 THEN 'FRESH'
        WHEN days_crawler_to_supply_processor <= 90 THEN '15 - 90'
        WHEN days_crawler_to_supply_processor <= 180 THEN '91 - 180'
        ELSE '180+'
    END AS freshness,
    ABS(days_crawler_to_supply_processor) < 15 AS is_fresh,
    days_crawler_to_supply_processor BETWEEN -14 AND -1 AS is_early_fresh,
    days_crawler_to_supply_processor,
    dt_crawler,
    dt_supply_processor
FROM
    joined_with_difference