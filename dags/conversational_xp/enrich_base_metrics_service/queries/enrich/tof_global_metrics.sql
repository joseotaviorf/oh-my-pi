/*
Table with user global metrics based on Top of Funnel (ToF) actions.
A ToF action is any search, recommendation, or Listing Page Viewed (LPV) interaction.
*/
WITH tof_actions AS (
    SELECT
        get_json_object(ids, '$.id_user') AS id_user,
        LOWER(get_json_object(dimensions, '$.business_context')) AS business_context,
        get_json_object(dimensions, '$.is_outlier_user') AS is_outlier_user,
        variants,
        CAST(get_json_object(timestamps, '$.ts_search') AS TIMESTAMP) AS ts_tof,
        date,
        year,
        month,
        day,
        week
    FROM
        datalake_search.search_impressions
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        AND get_json_object(ids, '$.id_user') IS NOT NULL
        AND LOWER(get_json_object(dimensions, '$.business_context')) IN ('rent', 'sale')
    UNION ALL
    SELECT
        get_json_object(ids, '$.id_user') AS id_user,
        LOWER(get_json_object(dimensions, '$.business_context')) AS business_context,
        get_json_object(dimensions, '$.is_outlier_user') AS is_outlier_user,
        variants,
        CAST(get_json_object(timestamps, '$.ts_recommendation') AS TIMESTAMP) AS ts_tof,
        date,
        year,
        month,
        day,
        week
    FROM
        datalake_search.recs_impressions_processed
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        AND get_json_object(ids, '$.id_user') IS NOT NULL
        AND LOWER(get_json_object(dimensions, '$.business_context')) IN ('rent', 'sale')
    UNION ALL
    SELECT
        get_json_object(ids, '$.id_user') AS id_user,
        LOWER(get_json_object(dimensions, '$.business_context')) AS business_context,
        get_json_object(dimensions, '$.is_outlier_user') AS is_outlier_user,
        variants,
        CAST(get_json_object(timestamps, '$.ts_lpv') AS TIMESTAMP) AS ts_tof,
        date,
        year,
        month,
        day,
        week
    FROM
        datalake_search.lpv_global_metrics
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        AND get_json_object(ids, '$.id_user') IS NOT NULL
        AND LOWER(get_json_object(dimensions, '$.business_context')) IN ('rent', 'sale')
),
tof_users AS (
    SELECT
        id_user,
        business_context,
        is_outlier_user,
        variants,
        date,
        year,
        month,
        day,
        week,
        MIN(ts_tof) AS min_ts_tof
    FROM
        tof_actions
    GROUP BY
        id_user,
        business_context,
        is_outlier_user,
        variants,
        date,
        year,
        month,
        day,
        week
),
house_cities AS (
    SELECT
        id_house,
        city
    FROM (
        SELECT
            id AS id_house,
            city,
            ROW_NUMBER() OVER (PARTITION BY id ORDER BY timestamp DESC) AS row_number
        FROM
            wonka.house_main
    ) AS ranked_houses
    WHERE
        row_number = 1
),
global_tof_metrics AS (
    SELECT
        TO_JSON(
            NAMED_STRUCT(
                'id_house', COALESCE(rent_flow.id_house, sale_flow.id_house),
                'id_user', tof_users.id_user,
                'id_agent', COALESCE(rent_flow.id_agent, sale_flow.id_agent)
            )
        ) AS ids,
        TO_JSON(
            NAMED_STRUCT(
                'business_context', tof_users.business_context,
                'city', house_cities.city,
                'is_primary_market',
                CASE
                    WHEN listing_sale_type.sale_type = 'PRIMARY' THEN 1
                    ELSE 0
                END,
                'is_outlier_user', tof_users.is_outlier_user,
                'visit_creation_origin', COALESCE(rent_flow.visit_creation_origin, sale_flow.visit_creation_origin)
            )
        ) AS dimensions,
        tof_users.variants,
        TO_JSON(
            NAMED_STRUCT(
                'tof', 1,
                'global_visit_booked',
                CASE
                    WHEN COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked) >= tof_users.min_ts_tof THEN 1
                    ELSE 0
                END,
                'global_visit_completed',
                CASE
                    WHEN COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed) >= tof_users.min_ts_tof THEN 1
                    ELSE 0
                END,
                'global_offer',
                CASE
                    WHEN COALESCE(rent_flow.ts_offer, sale_flow.ts_offer) >= tof_users.min_ts_tof THEN 1
                    ELSE 0
                END,
                'global_direct_offer',
                CASE
                    WHEN rent_flow.ts_direct_offer >= tof_users.min_ts_tof THEN 1
                    ELSE 0
                END,
                'global_submitted_offer',
                CASE
                    WHEN rent_flow.ts_offer_submitted >= tof_users.min_ts_tof THEN 1
                    ELSE 0
                END,
                'global_offer_approved',
                CASE
                    WHEN COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved) >= tof_users.min_ts_tof THEN 1
                    ELSE 0
                END,
                'global_contract_signed',
                CASE
                    WHEN COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed) >= tof_users.min_ts_tof THEN 1
                    ELSE 0
                END
            )
        ) AS metrics,
        TO_JSON(
            NAMED_STRUCT(
                'ts_tof', tof_users.min_ts_tof,
                'ts_global_visit_booked', COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked),
                'ts_global_visit_completed', COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed),
                'ts_global_offer', COALESCE(rent_flow.ts_offer, sale_flow.ts_offer),
                'ts_global_direct_offer', rent_flow.ts_direct_offer,
                'ts_global_submitted_offer', rent_flow.ts_offer_submitted,
                'ts_global_offer_approved', COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved),
                'ts_global_contract_signed', COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed)
            )
        ) AS timestamps,
        tof_users.date,
        tof_users.year,
        tof_users.month,
        tof_users.day,
        tof_users.week
    FROM
        tof_users
    LEFT JOIN
        datalake_search.rent_flow_past_30_days AS rent_flow
        ON tof_users.id_user = rent_flow.id_user
        AND tof_users.business_context = 'rent'
        AND rent_flow.ts_rent_flow_latest_event >= tof_users.min_ts_tof
    LEFT JOIN
        datalake_search.sale_flow_past_30_days AS sale_flow
        ON tof_users.id_user = sale_flow.id_user
        AND tof_users.business_context = 'sale'
        AND sale_flow.ts_sale_flow_latest_event >= tof_users.min_ts_tof
    LEFT JOIN
        house_cities
        ON COALESCE(rent_flow.id_house, sale_flow.id_house) = house_cities.id_house
    LEFT JOIN
        datalake_sale_primary_market.listing_sale_type AS listing_sale_type
        ON COALESCE(rent_flow.id_house, sale_flow.id_house) = listing_sale_type.id_house
)
SELECT
    ids,
    dimensions,
    variants,
    metrics,
    timestamps,
    date,
    year,
    month,
    day,
    week
FROM
    global_tof_metrics
