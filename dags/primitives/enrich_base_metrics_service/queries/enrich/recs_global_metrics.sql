/*
Table with all user global metrics (visits, offers, contracts) for recommendations
*/

------------------------------------------------------------------------------------
------------------------------ 1 - User Global Metrics -----------------------------
------------------------------------------------------------------------------------

-----------------
-- All Users - We fetch all users per day that interacted with recommendations

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
       MIN(ts_recommendation) AS min_ts_recommendation
FROM
  (
  SELECT get_json_object(ids, '$.id_user') AS id_user,
         get_json_object(dimensions, '$.business_context') AS business_context,
         get_json_object(dimensions, '$.is_outlier_user') AS is_outlier_user,
         get_json_object(timestamps, '$.ts_recommendation') AS ts_recommendation,
         variants,
         date,
         week,
         year,
         month,
         day
  FROM datalake_search.recs_impressions_processed
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
SELECT id_house,
       city
FROM
  (
  SELECT id AS id_house,
        city,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY timestamp DESC) as rn
  FROM wonka.house_main
  )
WHERE rn = 1
),

-----------------
-- We will now merge all users that interacted per day with the rent flow and sale flow.
-- This will allow us to know that a user did an offer after X days of interacting with a recommendation.
-- X is limited by days_past_30
global_user_recs_metrics AS (
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
                'recommendation', 1,
                'global_visit_booked', CASE WHEN COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked) >= all_users.date THEN 1 ELSE 0 END,
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
                    'ts_recommendation', all_users.min_ts_recommendation,
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
)

SELECT * FROM global_user_recs_metrics
