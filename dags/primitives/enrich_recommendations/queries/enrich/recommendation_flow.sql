WITH recommendation_to_rent_flow AS (
    SELECT
        id_rec,
        hours_between_rec_and_rent_flow <= 24 AS rec_to_rent_flow_one_day,
        hours_between_rec_and_rent_flow <= (24 * 7) AS rec_to_rent_flow_seven_days
    FROM (
        SELECT
            recommendation.id_rec,
            (
                CAST(item_interaction.ts_interaction as long)
                - CAST(recommendation.ts_rec_received as long)
            )
            / 3600 AS hours_between_rec_and_rent_flow,
            DENSE_RANK() OVER (
                PARTITION BY
                    recommendation.id_rec
                ORDER BY item_interaction.ts_interaction ASC
            )
            = 1 AS first_rent_flow_after_rec
        FROM datalake_recommendations.recommendation AS recommendation
        LEFT JOIN datalake_recommendations.item_interaction AS item_interaction
            ON
                recommendation.id_user = item_interaction.id_user
                AND recommendation.id_item = item_interaction.id_item
                AND recommendation.business_context = item_interaction.business_context
                AND recommendation.ts_rec_received <= item_interaction.ts_interaction
        WHERE interaction_type = 'rent-flow-created'
            AND recommendation.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
            AND item_interaction.dt_interaction BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    )
    WHERE
        first_rent_flow_after_rec IS TRUE
),

recommendation_to_sale_flow AS (
    SELECT
        id_rec,
        hours_between_rec_and_sale_flow <= 24 AS rec_to_sale_flow_one_day,
        hours_between_rec_and_sale_flow <= (24 * 14) AS rec_to_sale_flow_fourteen_days
    FROM (
        SELECT
            recommendation.id_rec,
            (
                CAST(item_interaction.ts_interaction as long)
                - CAST(recommendation.ts_rec_received as long)
            )
            / 3600 AS hours_between_rec_and_sale_flow,
            DENSE_RANK() OVER (
                PARTITION BY
                    recommendation.id_rec
                ORDER BY item_interaction.ts_interaction ASC
            )
            = 1 AS first_sale_flow_after_rec
        FROM datalake_recommendations.recommendation AS recommendation
        LEFT JOIN datalake_recommendations.item_interaction AS item_interaction
            ON
                recommendation.id_user = item_interaction.id_user
                AND recommendation.id_item = item_interaction.id_item
                AND recommendation.business_context = item_interaction.business_context
                AND recommendation.ts_rec_received
                <= item_interaction.ts_interaction
        WHERE interaction_type = 'sale-flow-created'
            AND recommendation.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
            AND item_interaction.dt_interaction BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    )
    WHERE
        first_sale_flow_after_rec IS TRUE
),

recommendation_to_favorite AS (
    SELECT
        id_rec,
        TRUE AS rec_to_favorite
    FROM (
        SELECT
            id_rec,
            (
                CAST(item_interaction.ts_interaction as long)
                - CAST(recommendation.ts_rec_received as long)
            )
            / 3600 AS hours_between_interaction_and_rec,
            DENSE_RANK() OVER (
                PARTITION BY
                    recommendation.id_rec
                ORDER BY item_interaction.ts_interaction ASC
            )
            = 1 AS first_favorite_after_rec
        FROM datalake_recommendations.recommendation AS recommendation
        LEFT JOIN datalake_recommendations.item_interaction AS item_interaction
            ON
                recommendation.id_user = item_interaction.id_user
                AND recommendation.id_item = item_interaction.id_item
                AND recommendation.business_context
                = item_interaction.business_context
                AND recommendation.ts_rec_received
                < item_interaction.ts_interaction
        WHERE interaction_type = 'house-favorited'
            AND recommendation.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
            AND item_interaction.dt_interaction BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    )
    /*
       We only keep the first interaction after each
       recommendation, to avoid cases in which the same item
       coming from the same recommendation is favorited multiple times
    */
    WHERE
        first_favorite_after_rec IS TRUE
        /*
        Important assumption: we consider a recommendation-to-favorite
        event only when a favorite event happened within 24 hours of the
        first recommendation visualization.
        */
        AND hours_between_interaction_and_rec <= 24
),

recommendation_to_click AS (
    SELECT
        id_rec,
        TRUE AS true_positive
    FROM (
        SELECT
            id_rec,
            (
                CAST(item_interaction.ts_interaction as long)
                - CAST(recommendation.ts_rec_received as long)
            )
            / 3600 AS hours_between_interaction_and_rec,
            DENSE_RANK() OVER (
                PARTITION BY
                    recommendation.id_rec
                ORDER BY item_interaction.ts_interaction ASC
            )
            = 1 AS first_click_after_rec
        FROM datalake_recommendations.recommendation AS recommendation
        LEFT JOIN datalake_recommendations.item_interaction AS item_interaction
            ON
                recommendation.id_user = item_interaction.id_user
                AND recommendation.id_item = item_interaction.id_item
                AND recommendation.business_context
                = item_interaction.business_context
                AND recommendation.ts_rec_received
                < item_interaction.ts_interaction
        WHERE
            (interaction_type = 'similar-house-clicked' AND  recommendation.display_type = 'similar-carousel')
            OR (interaction_type = 'listing-page-viewed')
            AND recommendation.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
            AND item_interaction.dt_interaction BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    )
    /*
       We only keep the first interaction after each
       recommendation, to avoid cases in which the same item
       coming from the same recommendation is clicked multiple times
    */
    WHERE
        first_click_after_rec IS TRUE
        AND hours_between_interaction_and_rec <= 24
),

recommendation_to_relevant_interaction AS (
    SELECT
        id_recset,
        COUNT(DISTINCT id_item) AS count_relevant_items
    FROM (
        SELECT DISTINCT
            id_recset,
            item_interaction.id_item,
            (
                CAST(item_interaction.ts_interaction as long)
                - CAST(recommendation.ts_rec_received as long)
            )
            / 3600 AS hours_between_interaction_and_rec,
            DENSE_RANK() OVER (
                PARTITION BY
                    recommendation.id_recset,
                    item_interaction.id_item
                ORDER BY item_interaction.ts_interaction ASC
            )
            = 1 AS first_relevant_interaction_after_rec
        FROM
            datalake_recommendations.recommendation AS recommendation
        LEFT JOIN
            datalake_recommendations.item_interaction AS item_interaction
            ON  recommendation.id_user = item_interaction.id_user
                AND recommendation.business_context = item_interaction.business_context
                AND recommendation.ts_rec_received < item_interaction.ts_interaction
        WHERE
            interaction_type in ('similar-house-clicked', 'listing-page-viewed', 'house-favorited')
            AND recommendation.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
            AND item_interaction.dt_interaction BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    )
    WHERE
        first_relevant_interaction_after_rec IS TRUE
        AND hours_between_interaction_and_rec <= 24
    GROUP BY 1
),

repeated_recommendation AS (
    SELECT DISTINCT
        recommendation.id_rec,
        TRUE AS repeated_rec
    FROM
        datalake_recommendations.recommendation AS recommendation
    INNER JOIN
        datalake_recommendations.recommendation AS past_recommendation
        ON
            recommendation.id_user = past_recommendation.id_user
            AND recommendation.display_type = past_recommendation.display_type
            AND recommendation.business_context = past_recommendation.business_context
            AND recommendation.id_item = past_recommendation.id_item
            AND recommendation.id_recset != past_recommendation.id_recset
            -- only considering recommendation between 1 day and 30 days old
            AND (
                CAST(TIMESTAMP(DATE(recommendation.ts_rec_received)) as long)
                - CAST(TIMESTAMP(DATE(past_recommendation.ts_rec_received)) as long)
            ) / 3600 between 24 AND (30*24)
)

SELECT
    recommendation.*,
    COALESCE(true_positive, FALSE) AS true_positive,
    SUM(INT(COALESCE(true_positive, FALSE))) OVER(PARTITION BY recommendation.id_recset ORDER BY item_rank) AS cum_true_positive,
    COALESCE(rec_to_favorite, FALSE) AS rec_to_favorite,
    COALESCE(recommendation_to_sale_flow.rec_to_sale_flow_one_day, FALSE) AS rec_to_sale_flow_one_day,
    COALESCE(recommendation_to_sale_flow.rec_to_sale_flow_fourteen_days, FALSE) AS rec_to_sale_flow_fourteen_days,
    COALESCE(recommendation_to_rent_flow.rec_to_rent_flow_one_day, FALSE) AS rec_to_rent_flow_one_day,
    COALESCE(recommendation_to_rent_flow.rec_to_rent_flow_seven_days, FALSE) AS rec_to_rent_flow_seven_days,
    COALESCE(recommendation_to_relevant_interaction.count_relevant_items, 0) AS count_relevant_items,
    COALESCE(repeated_recommendation.repeated_rec, FALSE) AS repeated_rec
FROM datalake_recommendations.recommendation AS recommendation
LEFT JOIN
    recommendation_to_click
    ON recommendation.id_rec = recommendation_to_click.id_rec
LEFT JOIN
    recommendation_to_favorite
    ON recommendation.id_rec = recommendation_to_favorite.id_rec
LEFT JOIN
    recommendation_to_sale_flow
    ON recommendation.id_rec = recommendation_to_sale_flow.id_rec
LEFT JOIN
    recommendation_to_rent_flow
    ON recommendation.id_rec = recommendation_to_rent_flow.id_rec
LEFT JOIN
    recommendation_to_relevant_interaction
    ON recommendation.id_recset = recommendation_to_relevant_interaction.id_recset
LEFT JOIN
    repeated_recommendation
    ON recommendation.id_rec = repeated_recommendation.id_rec
WHERE
    recommendation.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
