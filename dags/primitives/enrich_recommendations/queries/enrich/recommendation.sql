/*
This table contains all recommendations that were performed to users.

Assumptions:
  - We use similar carousel view events as proxy for the recommendation delivery
  - The schema should be generic enough to allow for recommendations coming from
    different channels/display types to coexist in this table
*/

WITH carousel_recommendations AS (
    SELECT
        "house" AS type_subject,
        "similar-carousel" AS display_type,
        "house-similarity-embeddings" AS ml_model,
        "house" AS type_item,
        country,
        region,
        city,
        device_family,
        platform,
        language,
        NULL as experiment,
        NULL as experiment_variant,
        ts_client_event AS ts_rec_created,
        ts_client_event AS ts_rec_received,
        year,
        month,
        day,
        COALESCE(id_user, id_amplitude) AS id_user,
        ARRAY(
            CAST(GET_JSON_OBJECT(event_properties, "$.house_id") AS INT)
        ) AS id_subjects,
        LOWER(
            GET_JSON_OBJECT(
                event_properties, "$.business_context"
            )
        ) AS business_context,
        ARRAY(
            CAST(GET_JSON_OBJECT(event_properties, "$.house_id") AS INT)
        ) AS id_anchors,
        POSEXPLODE(
            CAST(
                SPLIT(
                    REGEXP_REPLACE(
                        GET_JSON_OBJECT(event_properties, "$.similar_listings"),
                        '\\[|\\]|"',
                        ""
                    ),
                    ",",
                    -1
                ) AS ARRAY <INT>
            )
        ) AS (item_rank, id_item)
    FROM
        datalake_amplitude_clean.events
    WHERE
        event_type IN (
            "similar_carousel_viewed",
            "similar_carousel_viewed_native"
        )
        AND year = 2023
        AND month >= 4
        AND YEAR(ts_client_event) = year
        AND MONTH(ts_client_event) = month
        AND DAY(ts_client_event) = day
),

yellow_pages_recommendation_logs AS (
    /*
        This CTE extracts recommendation metadata from emlio
        logs that are sent by yellow-pages during the recommendation
        flow
    */
    WITH duplicated_yellow_pages_recommendations_logs AS (
        SELECT
            *,
            DENSE_RANK() OVER (PARTITION BY id_user, business_context, display_type, dt_email_sent ORDER BY ts_log) AS log_index
        FROM (
            SELECT
                CAST(
                    GET_JSON_OBJECT(emlio_logs.inputs, "$.user_id") as string
                ) AS id_user,
                LOWER(
                    GET_JSON_OBJECT(
                        emlio_logs.inputs, "$.business_context"
                    )
                ) AS business_context,
                LOWER(
                    GET_JSON_OBJECT(emlio_logs.inputs, "$.display_type")
                ) AS display_type,
                CAST(
                    SPLIT(
                        REGEXP_REPLACE(
                            GET_JSON_OBJECT(emlio_logs.inputs, "$.anchor_ids"),
                            '\\[|\\]|"',
                            ""
                        ),
                        ",",
                        -1
                    ) AS ARRAY <INT>
                ) AS id_anchors,
                CAST(
                    SPLIT(
                        REGEXP_REPLACE(
                            GET_JSON_OBJECT(emlio_logs.outputs, "$.house_ids"),
                            '\\[|\\]|"',
                            ""
                        ),
                        ",",
                        -1
                    ) AS ARRAY <INT>
                ) AS similar_listings,
                DATE(ts_log) AS dt_email_sent,
                ts_log
            FROM datalake_emlio_clean.emlio_logs AS emlio_logs
            WHERE
                emlio_logs.id_service = "yellow-pages"
                AND GET_JSON_OBJECT(emlio_logs.inputs, "$.anchor_ids") != "[]"
                AND year = 2023
                AND month >= 4
        )
    )

    SELECT
        id_user,
        business_context,
        display_type,
        dt_email_sent,
        id_anchors,
        similar_listings
    FROM duplicated_yellow_pages_recommendations_logs
    WHERE log_index = 1 AND display_type != "not_provided"
),

email_recommendation_delivered AS (
    /* This CTE takes event data from Braze */

    WITH emails_sent
     AS (
        SELECT
            sk_user_dispatch AS id_email,
            sk_user AS id_user,
            CASE
                WHEN
                    (
                        LOWER(campaign_name) LIKE "%dailyfeed%"
                        OR LOWER(campaign_name) LIKE "%daily-feed%"
                        /*
                          The following is a temporary solution for the change in recent campaign names.
                          The long-term solution will be to define a standard naming scheme for campaigns
                          such as personalization.<BUSINESS_CONTEXT>.<DISPLAY_TYPE>.<EXPERIMENT>.<VARIANT>
                        */
                        OR campaign_name LIKE "%NEW[CAMPAIGNS.DEMAND] forsale.listing.7day.similar_algorithm%"
                    )
                    THEN "daily_feed"
                WHEN
                    (LOWER(campaign_name) LIKE "%favorites%")
                    THEN "favorites_campaign"
            END AS display_type,
            CASE
                WHEN
                    LOWER(campaign_name) LIKE "%rent%"
                    THEN "rent"
                WHEN LOWER(campaign_name) LIKE "%sale%" THEN "sale"
            END AS business_context,
            CASE
                WHEN
                    campaign_name LIKE "%NEW[CAMPAIGNS.DEMAND] forsale.listing.7day.similar_algorithm%"
                    THEN "hue-for-sale-v1-experiment"
            END as experiment,
            CASE
                WHEN
                    campaign_name LIKE "%NEW[CAMPAIGNS.DEMAND] forsale.listing.7day.similar_algorithm.HUE.v1.sale.variant%"
                    THEN "treatment"
                WHEN
                    campaign_name LIKE "%NEW[CAMPAIGNS.DEMAND] forsale.listing.7day.similar_algorithm.baseline%"
                    THEN "control"
            END as experiment_variant,
            DATE(ts_email_sent) AS dt_email_sent,
            ts_email_first_opened AS ts_rec_created,
            COALESCE(ts_email_first_clicked, ts_email_first_opened) AS ts_rec_received
        FROM dw_braze.fact_campaign_user_dispatch AS fact_campaign_user_dispatch
        INNER JOIN
            dw_braze.dim_campaign AS dim_campaign
            ON dim_campaign.sk_campaign = fact_campaign_user_dispatch.sk_campaign
        WHERE
            event_channel = "email"
            AND (
                LOWER(campaign_name) LIKE "%dailyfeed%"
                OR LOWER(campaign_name) LIKE "%daily-feed%"
                OR LOWER(campaign_name) LIKE "%favorites%"
                -- Temporary workaround for recent changes on campaign names
                OR campaign_name LIKE "%NEW[CAMPAIGNS.DEMAND] forsale.listing.7day.similar_algorithm%"
            )
            AND (CAST(ts_email_first_opened as long) - CAST(ts_email_sent as long)) / 3600 <= 24
            AND (
                (CAST(ts_email_first_clicked as long) - CAST(ts_email_sent as long)) / 3600 <= 24
                OR ts_email_first_clicked IS NULL
            )
    )

    SELECT
      id_email,
      id_user,
      display_type,
      business_context,
      experiment,
      experiment_variant,
      dt_email_sent,
      MAX(ts_rec_created) AS ts_rec_created,
      MAX(ts_rec_received) AS ts_rec_received
    FROM emails_sent
    GROUP BY id_email, id_user, display_type, business_context, experiment, experiment_variant, dt_email_sent
),

email_user_sessions AS (
    SELECT
        id_user,
        id_session,
        -- We assume the following attributes are constant for the same session
        FIRST(business_context) AS business_context,
        FIRST(country) AS country,
        FIRST(region) AS region,
        FIRST(city) AS city,
        FIRST(device_family) AS device_family,
        FIRST(platform) AS platform,
        FIRST(language) AS language,
        FIRST(user_properties) AS user_properties,
        MIN(ts_event) AS ts_session
    FROM datalake_amplitude_clean.170698_listing_page_viewed_events
    WHERE
        id_user IS NOT NULL
        AND year = 2023
        AND month >= 4
    GROUP BY id_user, id_session
),

email_closest_session AS (
    /*
        This CTE joins email data with the closest Amplitude session for that user.
        We do this so we can retrieve session attributes that can be used for future
        deep dives (e.g. country, region, city, device_family, platform, language, etc)
    */
    WITH email_closest_sessions AS (
        SELECT
            id_email,
            id_session,
            country,
            region,
            city,
            device_family,
            platform,
            language,
            user_properties,
            ts_session,
            CAST(ts_session as long) - CAST(email_delivered.ts_rec_received as long) AS time_delta_session_email
        FROM email_recommendation_delivered AS email_delivered
        INNER JOIN email_user_sessions
            ON
                email_delivered.id_user = email_user_sessions.id_user
                AND email_delivered.business_context = email_user_sessions.business_context
                AND CASE
                    WHEN
                        email_delivered.ts_rec_received <= email_user_sessions.ts_session
                        AND ABS(
                            CAST(email_delivered.ts_rec_received as long)
                            - CAST(email_user_sessions.ts_session as long)
                        )
                        / 3600
                        <= 24
                        THEN 1
                    WHEN
                        email_delivered.ts_rec_received
                        > email_user_sessions.ts_session
                        AND ABS(
                            CAST(email_delivered.ts_rec_received as long)
                            - CAST(email_user_sessions.ts_session as long)
                        )
                        / 3600
                        <= (24 * 7)
                        THEN 1
                    ELSE 0
                END = 1
    ),

    email_closest_sessions_marked AS (
      SELECT
        email_closest_sessions.*,
        CASE
          -- if the delta between session and email is positive, we check to see if this is the first session after receiving the email
          WHEN time_delta_session_email > 0 AND  LAG(time_delta_session_email) OVER (PARTITION BY id_email ORDER BY ts_session) < 0 THEN TRUE
          -- if the delta between session and email is negative, we check to see if there is no other future session
          WHEN time_delta_session_email < 0 AND LEAD(time_delta_session_email) OVER (PARTITION BY id_email ORDER BY ts_session) IS NULL THEN TRUE
          ELSE FALSE
        END AS is_closest_session
      FROM email_closest_sessions
    )

    SELECT * FROM email_closest_sessions_marked
    WHERE is_closest_session IS TRUE
),

email_recommendations AS (
    SELECT
        yp_recs_logs.id_user,
        yp_recs_logs.id_anchors,
        email_delivered.ts_rec_created,
        email_delivered.ts_rec_received,
        email_delivered.display_type,
        email_delivered.business_context,
        email_delivered.experiment,
        email_delivered.experiment_variant,
        "house" AS type_item,
        email_closest_session.country,
        email_closest_session.region,
        email_closest_session.city,
        email_closest_session.device_family,
        email_closest_session.platform,
        email_closest_session.language,
        POSEXPLODE(yp_recs_logs.similar_listings) AS (item_rank, id_item),
        CASE
            WHEN
                email_delivered.business_context = "sale"
                THEN yp_recs_logs.id_anchors
            WHEN
                email_delivered.business_context = "rent"
                THEN CAST(ARRAY(yp_recs_logs.id_user) AS ARRAY <INT>)
        END AS id_subjects,
        CASE
            WHEN email_delivered.business_context = "sale" THEN "house"
            WHEN email_delivered.business_context = "rent" THEN "user"
        END AS type_subject,
        CASE
            WHEN
                email_delivered.business_context = "sale"
                THEN "house-similarity-embeddings"
            WHEN
                email_delivered.business_context = "rent"
                THEN "house-user-embeddings"
        END AS ml_model,
        YEAR(email_delivered.ts_rec_created) AS year,
        MONTH(email_delivered.ts_rec_created) AS month,
        DAY(email_delivered.ts_rec_created) AS day
    FROM email_recommendation_delivered AS email_delivered
    LEFT JOIN email_closest_session ON
        email_delivered.id_email = email_closest_session.id_email
    INNER JOIN
        yellow_pages_recommendation_logs AS yp_recs_logs ON
        email_delivered.id_user = yp_recs_logs.id_user
        AND email_delivered.business_context = yp_recs_logs.business_context
        AND email_delivered.display_type = yp_recs_logs.display_type
        AND email_delivered.dt_email_sent = yp_recs_logs.dt_email_sent
),

recommendations AS (
    SELECT
        id_user,
        id_item,
        id_subjects,
        id_anchors,
        ts_rec_created,
        ts_rec_received,
        business_context,
        type_subject,
        type_item,
        display_type,
        ml_model,
        country,
        region,
        city,
        device_family,
        platform,
        language,
        year,
        month,
        day,
        item_rank + 1 AS item_rank,
        experiment,
        experiment_variant
    FROM
        carousel_recommendations
    UNION ALL
    SELECT
        id_user,
        id_item,
        id_subjects,
        id_anchors,
        ts_rec_created,
        ts_rec_received,
        business_context,
        type_subject,
        type_item,
        display_type,
        ml_model,
        country,
        region,
        city,
        device_family,
        platform,
        language,
        year,
        month,
        day,
        item_rank + 1 AS item_rank,
        experiment,
        experiment_variant
    FROM email_recommendations
)

SELECT
    SHA2(
        CONCAT(
            recommendations.id_user,
            recommendations.id_item,
            recommendations.ts_rec_created,
            recommendations.business_context,
            recommendations.display_type
        ),
        256
    ) AS id_rec,
    SHA2(
        CONCAT(
            recommendations.id_user,
            recommendations.ts_rec_created,
            recommendations.business_context,
            recommendations.display_type
        ),
        256
    ) AS id_recset,
    recommendations.*
FROM recommendations
WHERE
    recommendations.id_item IS NOT NULL
    AND recommendations.id_anchors IS NOT NULL
    AND recommendations.business_context IS NOT NULL
    AND recommendations.year = 2023
    AND recommendations.month >= 4
    AND YEAR(recommendations.ts_rec_created) = 2023
    AND MONTH(recommendations.ts_rec_created) >= 4
