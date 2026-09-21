/*
Table with ids, dimensions, metrics and timestamps related to recommendations.
*/

------------------
-- Experiment Recs

-- Duplicate as in one line per recset_id / exp
WITH duplicate_experiment_recs AS (
    SELECT
        recset_id,
        recset_id_fix,
        experiments.experiment_name,
        experiments.variant_standard_name,
        CONCAT('"', experiments.experiment_name, '":"', variant_standard_name, '"') AS variants
    FROM datalake_search.recs_impressions
    INNER JOIN datalake_search.experiment_config_processed AS experiments
        ON experiments.variant_name = get_json_object(recs_impressions.user_properties, CONCAT("$['[Experiment] ", experiments.experiment_name, "']"))
        AND ts_recommendation >= experiments.begin_date
        AND (
            experiments.end_date IS NULL
            OR ts_recommendation <= experiments.end_date
            )
    WHERE MAKE_DATE(recs_impressions.year, recs_impressions.month, recs_impressions.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    GROUP BY 1,2,3,4,5
),

experiment_recs AS (
    SELECT
        recset_id_fix,
        recset_id,
        concat('{{', array_join(array_agg(variants), ','), '}}') AS variants
    FROM duplicate_experiment_recs
    GROUP BY 1,2
),

-----------------
-- Clicks

clicks AS (
    SELECT DISTINCT
        get_json_object(event_properties, '$.recset_id') recset_id,
        concat(get_json_object(event_properties, '$.recset_id'), '-', id_user, '-', id_session) AS recset_id_fix,
        ep_house_id AS id_house,
        1 AS click
    FROM datalake_amplitude_clean.170698_listing_page_viewed_events
    WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        AND get_json_object(event_properties, '$.recset_id') IS NOT NULL
),

-----------------
--House Published

recs_house_published AS (
    SELECT
        recs_impressions.id_house,
        recs_impressions.business_context,
        recs_impressions.recset_id,
        recs_impressions.recset_id_fix,
        MAX(house_publication_dates.ts_house_published) AS ts_house_published,
        LAST(city) AS city,
        LAST(is_classified) AS is_classified,
        LAST(CASE WHEN listing_sale_type.sale_type = 'PRIMARY' THEN 1 ELSE 0 END) AS is_primary_market
    FROM datalake_search.recs_impressions
    LEFT JOIN datalake_search.house_publication_dates
        ON house_publication_dates.id_house = recs_impressions.id_house
        AND UPPER(house_publication_dates.business_context) = recs_impressions.business_context
        AND house_publication_dates.ts_house_published <= recs_impressions.ts_recommendation
    LEFT JOIN wonka.house_main
        ON house_main.id = recs_impressions.id_house
    LEFT JOIN datalake_sale_primary_market.listing_sale_type AS listing_sale_type
        ON recs_impressions.id_house = listing_sale_type.id_house
    WHERE MAKE_DATE(recs_impressions.year, recs_impressions.month, recs_impressions.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    GROUP BY 1,2,3,4
)

-----------------
-- Final Query

SELECT DISTINCT
    --ids
    to_json(
        named_struct(
            'id_recset', recs_impressions.recset_id,
            'id_recset_fix', recs_impressions.recset_id_fix,
            'id_house', recs_impressions.id_house,
            'id_user', recs_impressions.id_user,
            'id_session', recs_impressions.id_session,
            'id_amplitude', recs_impressions.id_amplitude,
            'id_device', recs_impressions.id_device,
            'id_agent', COALESCE(rent_flow.id_agent, sale_flow.id_agent)
        )
    ) AS ids,

    -- dimensions
    to_json(
        named_struct(
            'business_context', recs_impressions.business_context,
            'city', recs_house_published.city,
            'platform', recs_impressions.platform,
            'position', recs_impressions.position,
            'showcase', recs_impressions.showcase,
            'origin', recs_impressions.origin,
            'listing_age', CAST(DATEDIFF(recs_impressions.ts_recommendation, recs_house_published.ts_house_published) AS INT),
            'is_classified', recs_house_published.is_classified,
            'is_primary_market', recs_house_published.is_primary_market,
            'is_outlier_user', CASE WHEN COALESCE(rent_outlier_users.id_user, sale_outlier_users.id_user) IS NOT NULL THEN 1 ELSE 0 END,
            'visit_creation_origin', COALESCE(rent_flow.visit_creation_origin, sale_flow.visit_creation_origin)
        )
    ) AS dimensions,

    --experimentation
    COALESCE(variants, '{{}}') AS variants,

    --metrics
    to_json(
        named_struct(
            'recommendations', 1,
            'click', COALESCE(clicks.click, 0),
            'offer', CASE WHEN COALESCE(rent_flow.ts_offer, sale_flow.ts_offer) >= recs_impressions.ts_recommendation THEN 1 ELSE 0 END,
            'direct_offer', CASE WHEN rent_flow.ts_direct_offer >= recs_impressions.ts_recommendation THEN 1 ELSE 0 END,
            'offer_submitted', CASE WHEN rent_flow.ts_offer_submitted >= recs_impressions.ts_recommendation THEN 1 ELSE 0 END,
            'offer_approved', CASE WHEN COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved) >= recs_impressions.ts_recommendation THEN 1 ELSE 0 END,
            'visit_booked', CASE WHEN COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked) >= recs_impressions.ts_recommendation THEN 1 ELSE 0 END,
            'visit_completed', CASE WHEN COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed) >= recs_impressions.ts_recommendation THEN 1 ELSE 0 END,
            'contract_signed', CASE WHEN COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed) >= recs_impressions.ts_recommendation THEN 1 ELSE 0 END
        )
    ) AS metrics,

    -- timestamps
    to_json(
        named_struct(
            'ts_recommendation', recs_impressions.ts_recommendation,
            'ts_house_published',  recs_house_published.ts_house_published,
            'ts_offer', COALESCE(rent_flow.ts_offer, sale_flow.ts_offer),
            'ts_direct_offer', rent_flow.ts_direct_offer,
            'ts_offer_submitted', rent_flow.ts_offer_submitted,
            'ts_offer_approved', COALESCE(rent_flow.ts_offer_approved, sale_flow.ts_offer_approved),
            'ts_visit_booked', COALESCE(rent_flow.ts_visit_booked, sale_flow.ts_visit_booked),
            'ts_visit_completed', COALESCE(rent_flow.ts_visit_completed, sale_flow.ts_visit_completed),
            'ts_contract_signed', COALESCE(rent_flow.ts_contract_signed, sale_flow.ts_contract_signed)
        )
    ) AS timestamps,

    recs_impressions.ts_recommendation AS ts_event,
    MAKE_DATE(recs_impressions.year, recs_impressions.month, recs_impressions.day) AS date,
    recs_impressions.year,
    recs_impressions.month,
    recs_impressions.day,
    WEEKOFYEAR(MAKE_DATE(recs_impressions.year, recs_impressions.month, recs_impressions.day)) AS week

FROM datalake_search.recs_impressions
LEFT JOIN recs_house_published
    ON recs_impressions.id_house = recs_house_published.id_house
    AND recs_impressions.business_context = recs_house_published.business_context
    AND recs_impressions.recset_id_fix = recs_house_published.recset_id_fix
LEFT JOIN experiment_recs
    ON recs_impressions.recset_id_fix = experiment_recs.recset_id_fix
LEFT JOIN clicks
    ON recs_impressions.recset_id_fix = clicks.recset_id_fix
    AND recs_impressions.id_house = clicks.id_house
LEFT JOIN datalake_search.rent_flow_past_30_days AS rent_flow
    ON recs_impressions.id_house = rent_flow.id_house
    AND recs_impressions.id_user = rent_flow.id_user
    AND recs_impressions.business_context = 'RENT'
LEFT JOIN datalake_search.sale_flow_past_30_days AS sale_flow
    ON recs_impressions.id_house = sale_flow.id_house
    AND recs_impressions.id_user = sale_flow.id_user
    AND recs_impressions.business_context = 'SALE'
LEFT JOIN datalake_search.rent_outlier_users_past_30_days as rent_outlier_users
    ON recs_impressions.id_user = rent_outlier_users.id_user
    AND recs_impressions.business_context = 'RENT'
LEFT JOIN datalake_search.sale_outlier_users_past_30_days as sale_outlier_users
    ON recs_impressions.id_user = sale_outlier_users.id_user
    AND recs_impressions.business_context = 'SALE'
WHERE MAKE_DATE(recs_impressions.year, recs_impressions.month, recs_impressions.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
