/*
Table with all user global metrics (visits, offers, contracts)
*/

------------------------------------------------------------------------------------
------------------------------ 1 - User Global Metrics -----------------------------
------------------------------------------------------------------------------------

-----------------
-- All Users - We fetch all user per day that interacted with search

WITH all_users AS (
SELECT id_user,
       business_context,
       is_outlier_user,
       variants,
       date,
       week,
       year,
       month,
       day,
       MIN(ts_search) AS min_ts_search
FROM
  (
  SELECT get_json_object(ids, '$.id_user') AS id_user,
         get_json_object(dimensions, '$.business_context') AS business_context,
         get_json_object(dimensions, '$.is_outlier_user') AS is_outlier_user,
         get_json_object(timestamps, '$.ts_search') AS ts_search,
         variants,
         date,
         week,
         year,
         month,
         day
  FROM datalake_search.search_impressions
  WHERE date BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
  )
  group by id_user,
           business_context,
           is_outlier_user,
           variants,
           date,
           week,
           year,
           month,
           day
),

house_cities AS (
SELECT id AS id_house,
       Last(city) AS city
FROM wonka.house_main
GROUP BY id
),

-----------------
-- We will now merge all users that interacted per day with the rent flow and sale flow.
-- This will allow us to know that a user did an offer after X days of interacting with a search.
-- X is limited by days_past_30
global_user_metrics AS (
    SELECT
           --ids
           to_json(
              named_struct(
                'id_house', COALESCE(rent_flow.id_house, sale_flow.id_house),
                'id_user', all_users.id_user
              )
            ) AS ids,

           --dimensions
           to_json(
              named_struct(
                'business_context', all_users.business_context,
                'city', house_cities.city,
                'is_outlier_user', all_users.is_outlier_user
              )
            ) AS dimensions,

            all_users.variants,

           --metrics
           to_json(
              named_struct(
                'search', 1,
                'global_visit_booked',CASE WHEN COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked) >= all_users.date THEN 1 ELSE 0 END,
                'global_visit_completed', CASE WHEN COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed) >= all_users.date THEN 1 ELSE 0 END,
                'global_offer', CASE WHEN COALESCE(rent_flow.ts_offer, sale_flow.ts_offer) >= all_users.date THEN 1 ELSE 0 END,
                'global_direct_offer', CASE WHEN rent_flow.ts_direct_offer >= all_users.date THEN 1 ELSE 0 END,
                'global_submitted_offer', CASE WHEN rent_flow.ts_offer_submitted >= all_users.date THEN 1 ELSE 0 END,
                'global_offer_approved', CASE WHEN COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved) >= all_users.date THEN 1 ELSE 0 END,
                'global_contract_signed', CASE WHEN COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed) >= all_users.date THEN 1 ELSE 0 END
              )
            ) AS metrics,

            -- timestamps
           to_json(
              named_struct(
                  'ts_search', all_users.min_ts_search,
                  'ts_global_visit_booked', COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked),
                  'ts_global_visit_completed', COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed),
                  'ts_global_offer', COALESCE(rent_flow.ts_offer, sale_flow.ts_offer),
                  'ts_global_direct_offer', rent_flow.ts_direct_offer,
                  'ts_global_submitted_offer', rent_flow.ts_offer_submitted,
                  'ts_global_offer_approved', COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved),
                  'ts_global_contract_signed', COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed)
              )
           ) AS timestamps,

           all_users.date,
           all_users.year,
           all_users.month,
           all_users.day,
           all_users.week

    FROM all_users
    LEFT JOIN datalake_search.rent_flow_past_30_days as rent_flow
                        ON all_users.id_user = rent_flow.id_user
                        AND all_users.business_context = 'rent'
                        AND ts_rent_flow_latest_event >= all_users.date
    LEFT JOIN datalake_search.sale_flow_past_30_days as sale_flow
                        ON all_users.id_user = sale_flow.id_user
                        AND all_users.business_context = 'sale'
                        AND ts_sale_flow_latest_event >= all_users.date
    LEFT JOIN house_cities ON COALESCE(rent_flow.id_house, sale_flow.id_house) = house_cities.id_house
),

------------------------------------------------------------------------------------
------------------------------ 2 - House Global Metrics ----------------------------
------------------------------------------------------------------------------------

-----------------
--House publication

houses_catalog AS (
    SELECT DISTINCT
        CAST(
            SUBSTRING(
                CAST(sk_house_listing AS STRING), 1, 9
            )
            AS INTEGER
        ) AS id_house,
        'rent' AS business_context,
        ts_status_start AS ts_house_published

    FROM
        dw_rent.fact_house_listing_status
    WHERE
        status_history IN ('publicado', 'PUBLISHED')
        AND ts_status_start IS NOT NULL
        AND country_code = 'BR'

    UNION ALL

    SELECT DISTINCT
        CAST(
            SUBSTRING(
                CAST(fact_listing_status.sk_sale_listing AS STRING),
                1, 9
            )
            AS INTEGER
        )
        AS id_house,
        'sale' AS business_context,
        fact_listing_status.ts_status_started AS ts_house_published
    FROM
        dw_sale.fact_listing_status AS fact_listing_status
    LEFT JOIN dw_public.dim_region AS dim_region
        ON fact_listing_status.sk_region = dim_region.sk_region
    WHERE
        fact_listing_status.status_history = 'PUBLISHED'
        AND fact_listing_status.ts_status_started IS NOT NULL
        AND dim_region.country_code = 'BR'
),

house_published_repeated AS (
  SELECT
    id_house,
    ts_house_published,
    business_context,
    LAG(ts_house_published) OVER (PARTITION BY id_house, business_context ORDER BY ts_house_published) AS ts_house_published_shift
  FROM
    houses_catalog
),

houses_published AS (
    SELECT
        id_house,
        business_context,
        ts_house_published,
        CONCAT('{{', array_join(array_agg(CONCAT('"', experiment_config.experiment_name, '":"all"')), ','), '}}') AS variants
    FROM
        house_published_repeated
    LEFT JOIN
        datalake_search.experiment_config AS experiment_config
        ON experiment_config.config.begin_date <= ts_house_published
        AND (experiment_config.config.end_date >= ts_house_published OR experiment_config.config.end_date IS NULL)
    WHERE
        COALESCE(DATEDIFF(ts_house_published, ts_house_published_shift), 1000) > 84
    GROUP BY
        id_house,
        business_context,
        ts_house_published
),

parsed_houses_published AS (
    SELECT
        houses_published.id_house,
        houses_published.business_context,
        house_cities.city,
        variants,
        houses_published.ts_house_published,
        DATE(houses_published.ts_house_published) AS date,
        YEAR(houses_published.ts_house_published) AS year,
        MONTH(houses_published.ts_house_published) AS month,
        DAY(houses_published.ts_house_published) AS day,
        WEEKOFYEAR(houses_published.ts_house_published) AS week
    FROM
      houses_published
    LEFT JOIN house_cities
        ON houses_published.id_house = house_cities.id_house
    WHERE houses_published.ts_house_published BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
),

global_house_metrics AS (
    SELECT
    --ids
    to_json(
       named_struct(
         'id_house', houses_published.id_house,
         'id_user', get_json_object(global_user_metrics.ids, '$.id_user')
       )
     ) AS ids,

    -- dimensions
    to_json(
            named_struct(
                'business_context', houses_published.business_context,
                'city', house_cities.city,
                'is_outlier_user', get_json_object(global_user_metrics.dimensions, '$.is_outlier_user')
            )
    ) AS dimensions,

    -- variants
    CASE WHEN global_user_metrics.variants != "{{}}" THEN global_user_metrics.variants ELSE houses_published.variants END as variants,

    --metrics
    to_json(
            named_struct(
                'house_published', 1,
                'global_visit_booked', CASE WHEN get_json_object(global_user_metrics.timestamps, '$.ts_global_visit_booked') >= houses_published.date THEN 1 ELSE 0 END,
                'global_visit_completed', CASE WHEN get_json_object(global_user_metrics.timestamps, '$.ts_global_visit_completed') >= houses_published.date THEN 1 ELSE 0 END,
                'global_offer', CASE WHEN get_json_object(global_user_metrics.timestamps, '$.ts_global_offer') >= houses_published.date THEN 1 ELSE 0 END,
                'global_offer_approved', CASE WHEN get_json_object(global_user_metrics.timestamps, '$.ts_global_offer_approved') >= houses_published.date THEN 1 ELSE 0 END,
                'global_contract_signed', CASE WHEN get_json_object(global_user_metrics.timestamps, '$.ts_global_contract_signed') >= houses_published.date THEN 1 ELSE 0 END
            )
    ) AS metrics,

    -- timestamps
    to_json(
            named_struct(
                'ts_house_published', houses_published.ts_house_published,
                'ts_global_visit_booked', get_json_object(global_user_metrics.timestamps, '$.ts_global_visit_booked'),
                'ts_global_visit_completed', get_json_object(global_user_metrics.timestamps, '$.ts_global_visit_completed'),
                'ts_global_offer', get_json_object(global_user_metrics.timestamps, '$.ts_global_offer') ,
                'ts_global_offer_approved', get_json_object(global_user_metrics.timestamps, '$.ts_global_offer_approved') ,
                'ts_global_contract_signed', get_json_object(global_user_metrics.timestamps, '$.ts_global_contract_signed')
            )
    ) AS timestamps,

    houses_published.date,
    houses_published.year,
    houses_published.month,
    houses_published.day,
    houses_published.week

    FROM parsed_houses_published as houses_published
    LEFT JOIN house_cities ON houses_published.id_house = house_cities.id_house
    LEFT JOIN global_user_metrics ON houses_published.id_house = get_json_object(global_user_metrics.ids, '$.id_house')
                                  AND houses_published.date <= global_user_metrics.date
                                  AND houses_published.business_context = get_json_object(global_user_metrics.dimensions, '$.business_context')

    WHERE houses_published.date BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
),

-- This is used to have a the correct denominator is the metrics calculation.
house_published_all AS (
    SELECT
    --ids
    to_json(
       named_struct(
         'id_house', houses_published.id_house
       )
     ) AS ids,

    -- dimensions
    to_json(
            named_struct(
                'business_context', houses_published.business_context,
                'city', house_cities.city
            )
    ) AS dimensions,

    -- variants
    houses_published.variants as variants,

    --metrics
    to_json(
            named_struct(
                'house_published', 1
            )
    ) AS metrics,

    -- timestamps
    to_json(
            named_struct(
                'ts_house_published', houses_published.ts_house_published
            )
    ) AS timestamps,

    houses_published.date,
    houses_published.year,
    houses_published.month,
    houses_published.day,
    houses_published.week

    FROM parsed_houses_published as houses_published
    LEFT JOIN house_cities ON houses_published.id_house = house_cities.id_house
    WHERE houses_published.date BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)


------------------------------------------------------------------------------------
--------------------------- 3 - User House Global Metrics --------------------------
------------------------------------------------------------------------------------
-- By doing this we will have duplicated entries for the same offer as in one table we are looking in the user POI and in the other
-- we are looking at the house POI. Yet, if we do the correct group by we will be able to calculate any global metric.
SELECT * FROM global_user_metrics
UNION
SELECT * FROM global_house_metrics
UNION
SELECT * FROM house_published_all
