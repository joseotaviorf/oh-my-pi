/*
Table with user global metrics based on Listing Page Viewed (LPV) events.
*/
WITH listing_page_viewed AS (
    SELECT
        COALESCE(
            CAST(ep_house_id AS STRING),
            get_json_object(event_properties, '$.house_id')
        ) AS id_house,
        id_user,
        LOWER(business_context) AS business_context,
        user_properties,
        ts_event AS ts_lpv,
        DATE(ts_event) AS date,
        YEAR(ts_event) AS year,
        MONTH(ts_event) AS month,
        DAY(ts_event) AS day,
        WEEKOFYEAR(ts_event) AS week
    FROM
        datalake_amplitude_clean.170698_listing_page_viewed_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        AND LOWER(business_context) IN ('rent', 'sale')
        AND id_user IS NOT NULL
        AND COALESCE(
            CAST(ep_house_id AS STRING),
            get_json_object(event_properties, '$.house_id')
        ) IS NOT NULL
        AND get_json_object(user_properties, '$.country') = 'BR'
),
lpv_users AS (
    SELECT
        id_house,
        id_user,
        business_context,
        date,
        year,
        month,
        day,
        week,
        MIN(ts_lpv) AS min_ts_lpv
    FROM
        listing_page_viewed
    GROUP BY
        id_house,
        id_user,
        business_context,
        date,
        year,
        month,
        day,
        week
),
duplicate_experiment_lpvs AS (
    SELECT DISTINCT
        listing_page_viewed.id_house,
        listing_page_viewed.id_user,
        listing_page_viewed.business_context,
        listing_page_viewed.date,
        CONCAT(
            '"',
            experiments.experiment_name,
            '":"',
            experiments.variant_standard_name,
            '"'
        ) AS variants
    FROM
        listing_page_viewed
    INNER JOIN
        datalake_search.experiment_config_processed AS experiments
        ON experiments.variant_name = get_json_object(
            listing_page_viewed.user_properties,
            CONCAT("$['[Experiment] ", experiments.experiment_name, "']")
        )
        AND listing_page_viewed.ts_lpv >= experiments.begin_date
        AND (
            experiments.end_date IS NULL
            OR listing_page_viewed.ts_lpv <= experiments.end_date
        )
),
experiment_lpvs AS (
    SELECT
        id_house,
        id_user,
        business_context,
        date,
        CONCAT('{{', ARRAY_JOIN(ARRAY_SORT(COLLECT_SET(variants)), ','), '}}') AS variants
    FROM
        duplicate_experiment_lpvs
    GROUP BY
        id_house,
        id_user,
        business_context,
        date
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
    )
    WHERE
        row_number = 1
),
global_lpv_metrics AS (
    SELECT
        TO_JSON(
            NAMED_STRUCT(
                'id_house', lpv_users.id_house,
                'id_user', lpv_users.id_user,
                'id_agent', COALESCE(rent_flow.id_agent, sale_flow.id_agent)
            )
        ) AS ids,
        TO_JSON(
            NAMED_STRUCT(
                'business_context', lpv_users.business_context,
                'city', house_cities.city,
                'is_primary_market',
                CASE
                    WHEN listing_sale_type.sale_type = 'PRIMARY' THEN 1
                    ELSE 0
                END,
                'is_outlier_user',
                CASE
                    WHEN COALESCE(rent_outlier_users.id_user, sale_outlier_users.id_user) IS NOT NULL THEN 1
                    ELSE 0
                END,
                'visit_creation_origin', COALESCE(rent_flow.visit_creation_origin, sale_flow.visit_creation_origin)
            )
        ) AS dimensions,
        COALESCE(experiment_lpvs.variants, '{{}}') AS variants,
        TO_JSON(
            NAMED_STRUCT(
                'lpv', 1,
                'global_visit_booked',
                CASE
                    WHEN COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked) >= lpv_users.min_ts_lpv THEN 1
                    ELSE 0
                END,
                'global_visit_completed',
                CASE
                    WHEN COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed) >= lpv_users.min_ts_lpv THEN 1
                    ELSE 0
                END,
                'global_offer',
                CASE
                    WHEN COALESCE(rent_flow.ts_offer, sale_flow.ts_offer) >= lpv_users.min_ts_lpv THEN 1
                    ELSE 0
                END,
                'global_direct_offer',
                CASE
                    WHEN rent_flow.ts_direct_offer >= lpv_users.min_ts_lpv THEN 1
                    ELSE 0
                END,
                'global_submitted_offer',
                CASE
                    WHEN rent_flow.ts_offer_submitted >= lpv_users.min_ts_lpv THEN 1
                    ELSE 0
                END,
                'global_offer_approved',
                CASE
                    WHEN COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved) >= lpv_users.min_ts_lpv THEN 1
                    ELSE 0
                END,
                'global_contract_signed',
                CASE
                    WHEN COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed) >= lpv_users.min_ts_lpv THEN 1
                    ELSE 0
                END
            )
        ) AS metrics,
        TO_JSON(
            NAMED_STRUCT(
                'ts_lpv', lpv_users.min_ts_lpv,
                'ts_global_visit_booked', COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked),
                'ts_global_visit_completed', COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed),
                'ts_global_offer', COALESCE(rent_flow.ts_offer, sale_flow.ts_offer),
                'ts_global_direct_offer', rent_flow.ts_direct_offer,
                'ts_global_submitted_offer', rent_flow.ts_offer_submitted,
                'ts_global_offer_approved', COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved),
                'ts_global_contract_signed', COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed)
            )
        ) AS timestamps,
        lpv_users.date,
        lpv_users.year,
        lpv_users.month,
        lpv_users.day,
        lpv_users.week
    FROM
        lpv_users
    LEFT JOIN
        experiment_lpvs
        ON lpv_users.id_house = experiment_lpvs.id_house
        AND lpv_users.id_user = experiment_lpvs.id_user
        AND lpv_users.business_context = experiment_lpvs.business_context
        AND lpv_users.date = experiment_lpvs.date
    LEFT JOIN
        datalake_search.rent_flow_past_30_days AS rent_flow
        ON lpv_users.id_house = rent_flow.id_house
        AND lpv_users.id_user = rent_flow.id_user
        AND lpv_users.business_context = 'rent'
        AND rent_flow.ts_rent_flow_latest_event >= lpv_users.min_ts_lpv
    LEFT JOIN
        datalake_search.sale_flow_past_30_days AS sale_flow
        ON lpv_users.id_house = sale_flow.id_house
        AND lpv_users.id_user = sale_flow.id_user
        AND lpv_users.business_context = 'sale'
        AND sale_flow.ts_sale_flow_latest_event >= lpv_users.min_ts_lpv
    LEFT JOIN
        datalake_search.rent_outlier_users_past_30_days AS rent_outlier_users
        ON lpv_users.id_user = rent_outlier_users.id_user
        AND lpv_users.business_context = 'rent'
    LEFT JOIN
        datalake_search.sale_outlier_users_past_30_days AS sale_outlier_users
        ON lpv_users.id_user = sale_outlier_users.id_user
        AND lpv_users.business_context = 'sale'
    LEFT JOIN
        house_cities
        ON lpv_users.id_house = house_cities.id_house
    LEFT JOIN
        datalake_sale_primary_market.listing_sale_type AS listing_sale_type
        ON lpv_users.id_house = listing_sale_type.id_house
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
    global_lpv_metrics
