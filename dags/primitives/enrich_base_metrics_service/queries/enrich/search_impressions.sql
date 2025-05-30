/*
Table with ids, dimensions, metrics and timestamps related to search.
*/

-----------------
-- Union SPVS

WITH union_spvs AS (
    SELECT
        event_properties,
        user_properties,
        id_user,
        id_session,
        id_amplitude,
        id_device,
        "spv" as search_rendering_type,
        ts_event
    FROM
        datalake_amplitude_clean_staging.170698_search_page_viewed_events
    WHERE
        -- include one more day to make sure we don't repeat id_search that start before midnight and end after.
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30} + 1) AND DATE('{end_date}')
        AND get_json_object(event_properties, '$.search_id') IS NOT NULL
        AND get_json_object(event_properties, '$.search_results_list') IS NOT NULL
        AND get_json_object(event_properties, '$.search_results_list') <> '[]'
        AND get_json_object(user_properties, '$.country') = 'BR'
        AND id_user IS NOT NULL

    UNION ALL

    SELECT
        event_properties,
        user_properties,
        id_user,
        id_session,
        id_amplitude,
        id_device,
        "srpv" as search_rendering_type,
        ts_event
    FROM
        datalake_amplitude_clean_staging.170698_search_results_page_viewed_events
    WHERE
        -- include one more day to make sure we don't repeat id_search that start before midnight and end after.
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30} + 1) AND DATE('{end_date}')
        AND get_json_object(event_properties, '$.search_id') IS NOT NULL
        AND get_json_object(event_properties, '$.search_results_list') IS NOT NULL
        AND get_json_object(event_properties, '$.search_results_list') <> '[]'
        AND get_json_object(user_properties, '$.country') = 'BR'
        AND id_user IS NOT NULL
),

-----------------
-- Searches

duplicated_searches AS
(
    SELECT
        -- ids
        get_json_object(union_spvs.event_properties, '$.search_id') AS id_search,

        id_user,
        id_session,
        id_amplitude,
        id_device,

        -- dimensions
        get_json_object(event_properties, '$.business_context') AS business_context,
        get_json_object(user_properties, '$.platform') AS device_type,
        get_json_object(event_properties, '$.sort_order') as sort_order,
        get_json_object(event_properties, '$.copilot_session_id') as copilot_session_id,

        -- event_timestamps
        union_spvs.ts_event,

        ROW_NUMBER() OVER (
            PARTITION BY
                get_json_object(union_spvs.event_properties, '$.search_id')
            ORDER BY
                ts_event,
                -- in principle ts_event should be enough but,
                -- if there are multiple rows with different information (due to bugs) the next code makes the query deterministic
                id_user,
                id_session,
                id_amplitude,
                id_device,
                get_json_object(event_properties, '$.business_context'),
                get_json_object(user_properties, '$.platform'),
                get_json_object(event_properties, '$.sort_order'),
                get_json_object(event_properties, '$.copilot_session_id')
        ) AS row_n

    FROM union_spvs
),

searches AS (
    SELECT DISTINCT
        * ,
        CASE
            WHEN device_type IN ("android", "ios") THEN "app"
            WHEN device_type IN ("web_desktop", "web_mobile") THEN "web"
            ELSE "None"
        END AS platform
    FROM
        duplicated_searches
    WHERE
        row_n = 1
),


-----------------
-- Experiment Searches


duplicate_experiment_searches AS
(
    SELECT
        get_json_object(union_spvs.event_properties, '$.search_id') AS id_search,
        experiments.experiment_name,
        experiments.variant_standard_name,
        ROW_NUMBER() OVER (
            PARTITION BY
                get_json_object(union_spvs.event_properties, '$.search_id'),
                experiments.experiment_name
            ORDER BY
                ts_event
        ) AS row_n

    FROM
        union_spvs
    INNER JOIN datalake_search.experiment_config_processed AS experiments
        ON experiments.variant_name = get_json_object(union_spvs.user_properties, CONCAT('$.', experiments.experiment_name))
        AND (
            (ts_event >= experiments.begin_date)
            AND (experiments.end_date IS NULL OR ts_event <= experiments.end_date)
        )
),

experiment_searches_not_json AS (
    SELECT DISTINCT
    id_search,
    CONCAT('"', duplicate_experiment_searches.experiment_name, '":"', variant_standard_name, '"') AS variants
FROM duplicate_experiment_searches
WHERE row_n = 1
),

experiment_searches AS (
    SELECT
    id_search,
    concat('{{', array_join(array_agg(variants), ','), '}}') AS variants
FROM experiment_searches_not_json
GROUP BY id_search
),

-----------------
-- Metrics

-----------------
-- Clicks

clicks AS (
    SELECT DISTINCT
        get_json_object(event_properties, '$.search_id') id_search,
        ep_house_id AS id_house,
        1 AS click
    FROM datalake_amplitude_clean.170698_listing_page_viewed_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        AND get_json_object(event_properties, '$.from_route') = "search_results"
        AND get_json_object(event_properties, '$.search_id') IS NOT NULL
),

-----------------
--Granularity Search  House

-----------------
--Houses Rank

search_house AS (
    SELECT
        get_json_object(event_properties, '$.search_id') AS id_search,
        POSEXPLODE(split(regexp_replace(get_json_object(event_properties, '$.search_results_list'), '\\[|\\]|"', ''),",")) AS (page_position, id_house),
        get_json_object(event_properties, '$.business_context') AS business_context,
        get_json_object(user_properties, '$.platform') AS device_type,
        get_json_object(event_properties, '$.view_mode') as view_mode,
        search_rendering_type,
        ts_event
    FROM
        union_spvs
),

abs_position AS (
    SELECT
        id_search,
        id_house,
        FIRST(device_type) OVER (PARTITION BY id_search) AS device_type,
        FIRST(view_mode) OVER (PARTITION BY id_search) AS view_mode,
        FIRST(search_rendering_type) OVER (PARTITION BY id_search) AS search_rendering_type,
        FIRST(business_context) OVER (PARTITION BY id_search) AS business_context,
        MIN(ts_event) OVER (PARTITION BY id_search) AS ts_search,
        DENSE_RANK() OVER(PARTITION BY id_search ORDER BY ts_event, page_position) AS absolute_position,
        DENSE_RANK() OVER(PARTITION BY id_search ORDER BY ts_event) AS page_number
    FROM
        search_house
),

min_abs_position AS (
    SELECT
        id_search,
        id_house,
        business_context,
        device_type,
        view_mode,
        search_rendering_type,
        ts_search,
        MIN(absolute_position) AS absolute_position,
        MIN(page_number) AS page_number
    FROM
        abs_position
    GROUP BY
        id_search,
        id_house,
        business_context,
        device_type,
        view_mode,
        search_rendering_type,
        ts_search
),

houses_rank AS (
    SELECT id_search,
        id_house,
        business_context,
        search_rendering_type,
        CASE
            WHEN device_type IN ("android", "ios") AND view_mode == "map" THEN "LTR"
            WHEN device_type IN ("web_desktop", "web_mobile") AND search_rendering_type == "spv" THEN "LTR"
            ELSE "pclick"
        END AS rank_model,
        ts_search,
        DENSE_RANK() OVER(PARTITION BY id_search ORDER BY absolute_position) AS absolute_position,
        DENSE_RANK() OVER(PARTITION BY id_search ORDER BY page_number) AS page_number,
        DENSE_RANK() OVER(PARTITION BY id_search, page_number ORDER BY absolute_position) AS page_position
    FROM
        min_abs_position
),

-----------------
--Houses Cities

house_cities AS (
    SELECT
        id AS id_house,
        Last(city) AS city
    FROM
        wonka.house_main
    GROUP BY
        id
),

-----------------
--Exploded Houses

exploded_houses AS (
    SELECT
        houses_rank.id_search,
        houses_rank.id_house,
        house_cities.city,
        houses_rank.search_rendering_type,
        houses_rank.rank_model,
        houses_rank.absolute_position,
        houses_rank.page_number,
        houses_rank.page_position,
        MAX(houses_published.ts_house_published) AS ts_house_published,
        CAST(DATEDIFF(FIRST(houses_rank.ts_search), MAX(houses_published.ts_house_published)) AS INT) AS listing_age
    FROM
        houses_rank
    LEFT JOIN datalake_search.house_publication_dates houses_published
        ON houses_rank.id_house = houses_published.id_house
        AND houses_rank.business_context = houses_published.business_context
        AND houses_published.ts_house_published <= houses_rank.ts_search
    LEFT JOIN house_cities
        ON houses_rank.id_house = house_cities.id_house
    GROUP BY
        houses_rank.id_search,
        houses_rank.id_house,
        house_cities.city,
        houses_rank.search_rendering_type,
        houses_rank.rank_model,
        houses_rank.absolute_position,
        houses_rank.page_number,
        houses_rank.page_position
)

-----------------
-- Final Query

SELECT
    --ids
    to_json(
        named_struct(
            'id_search', searches.id_search,
            'id_house', exploded_houses.id_house,
            'id_user', searches.id_user,
            'id_session', searches.id_session,
            'id_amplitude', searches.id_amplitude,
            'id_device', searches.id_device,
            'copilot_session_id', searches.copilot_session_id
        )
    ) AS ids,

    -- dimensions
    to_json(
        named_struct(
            'business_context', searches.business_context,
            'city', exploded_houses.city,
            'device_type', searches.device_type,
            'platform', searches.platform,
            'sort_order', searches.sort_order,
            'search_rendering_type', exploded_houses.search_rendering_type,
            'rank_model', exploded_houses.rank_model,
            'absolute_position', exploded_houses.absolute_position,
            'page_number', exploded_houses.page_number,
            'page_position', exploded_houses.page_position,
            'listing_age', exploded_houses.listing_age,
            'is_outlier_user', CASE WHEN COALESCE(rent_outlier_users.id_user, sale_outlier_users.id_user) IS NOT NULL THEN 1 ELSE 0 END
        )
    ) AS dimensions,

    --experimentation
    COALESCE(variants, '{{}}') AS variants,

    --metrics
    to_json(
        named_struct(
            'search', 1,
            'click', COALESCE(clicks.click, 0),
            'visit_booked', CASE WHEN COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked) >= searches.ts_event THEN 1 ELSE 0 END,
            'visit_completed', CASE WHEN COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed) >= searches.ts_event THEN 1 ELSE 0 END,
            'offer', CASE WHEN COALESCE(rent_flow.ts_offer, sale_flow.ts_offer) >= searches.ts_event THEN 1 ELSE 0 END,
            'direct_offer', CASE WHEN rent_flow.ts_direct_offer >= searches.ts_event THEN 1 ELSE 0 END,
            'offer_submitted', CASE WHEN rent_flow.ts_offer_submitted >= searches.ts_event THEN 1 ELSE 0 END,
            'offer_approved', CASE WHEN COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved) >= searches.ts_event THEN 1 ELSE 0 END,
            'contract_signed', CASE WHEN COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed) >= searches.ts_event THEN 1 ELSE 0 END,
            'relevant_search',
            MAX(
                CASE WHEN (
                    clicks.click = 1
                    OR COALESCE(rent_flow.ts_offer, sale_flow.ts_offer) >= searches.ts_event
                    OR COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed) >= searches.ts_event
                    OR COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed) >= searches.ts_event
                ) THEN 1 ELSE 0 END
            ) OVER(PARTITION BY searches.id_search)
        )
    ) AS metrics,

    -- timestamps
    to_json(
        named_struct(
            'ts_search', searches.ts_event,
            'ts_house_published', exploded_houses.ts_house_published,
            'ts_visit_booked', COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked),
            'ts_visit_completed', COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed),
            'ts_offer', COALESCE(rent_flow.ts_offer, sale_flow.ts_offer),
            'ts_direct_offer', rent_flow.ts_direct_offer,
            'ts_offer_submitted', rent_flow.ts_offer_submitted,
            'ts_offer_approved', COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved),
            'ts_contract_signed', COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed)
        )
    ) AS timestamps,

    searches.ts_event,
    DATE(searches.ts_event) AS date,
    YEAR(searches.ts_event) AS year,
    MONTH(searches.ts_event) AS month,
    DAY(searches.ts_event) AS day,
    WEEKOFYEAR(searches.ts_event) AS week

FROM searches
LEFT JOIN experiment_searches
    ON searches.id_search = experiment_searches.id_search
LEFT JOIN exploded_houses
    ON searches.id_search = exploded_houses.id_search
LEFT JOIN clicks
    ON searches.id_search = clicks.id_search
    AND exploded_houses.id_house = clicks.id_house
LEFT JOIN datalake_search.rent_flow_past_30_days as rent_flow
    ON exploded_houses.id_house = rent_flow.id_house
    AND searches.id_user = rent_flow.id_user
    AND searches.business_context = 'rent'
LEFT JOIN datalake_search.sale_flow_past_30_days as sale_flow
    ON exploded_houses.id_house = sale_flow.id_house
    AND searches.id_user = sale_flow.id_user
    AND searches.business_context = 'sale'
LEFT JOIN datalake_search.rent_outlier_users_past_30_days as rent_outlier_users
    ON searches.id_user = rent_outlier_users.id_user
    AND searches.business_context = 'rent'
LEFT JOIN datalake_search.sale_outlier_users_past_30_days as sale_outlier_users
    ON searches.id_user = sale_outlier_users.id_user
    AND searches.business_context = 'sale'
WHERE searches.ts_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
