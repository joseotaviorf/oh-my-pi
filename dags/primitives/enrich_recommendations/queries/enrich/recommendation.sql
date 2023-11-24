/*
This table contains all recommendations that were performed to users.

Assumptions:
  - We use similar carousel view events as proxy for the recommendation delivery
  - The schema should be generic enough to allow for recommendations coming from
    different channels/display types to coexist in this table
*/

WITH yellow_pages_recommendation_logs AS (
    /*
    For each recommendation generated on yellow-pages we log one message to
    emlio, which contain relevant information about the recommendation that
    is not necessarily available on other sources (e.g. experiment, experiment variant)
    */
    SELECT
        id_user,
        business_context,
        display_type,
        id_anchors,
        similar_listings,
        experiments,
        experiments_variants,
        ts_log,
        dt_log
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
            ARRAY_DISTINCT(
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
                )
            ) AS id_anchors,
            ARRAY_DISTINCT(
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
                )
            ) AS similar_listings,
            -- Multiple experiments can be active at the same time
            MAP_KEYS(
              FROM_JSON(
                GET_JSON_OBJECT(inputs, "$.experiment_settings"), "map<string, string>"
              )
            ) AS experiments,
            MAP_VALUES(
              from_json(
                GET_JSON_OBJECT(inputs, "$.experiment_settings"), "map<string, string>"
              )
            ) AS experiments_variants,
            DATE(ts_log) AS dt_log,
            ts_log
        FROM datalake_emlio_clean.emlio_logs AS emlio_logs
        WHERE
            emlio_logs.id_service = "yellow-pages"
            AND MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    )
),


carousel_recommendations AS (
    /*
        This CTE extracts recommendation metadata from Amplitude
        events that are sent by
    */
    WITH carousel_recommendation_delivered AS (
        SELECT DISTINCT
            "house" AS type_subject,
            "house-similarity-embeddings" AS ml_model,
            "house" AS type_item,
            country,
            region,
            city,
            device_family,
            platform,
            language,
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
                ARRAY_DISTINCT(
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
                )
            ) AS (item_rank, id_item)
        FROM
            datalake_amplitude_clean.events
        WHERE
            /* TODO: include recommendation feed events */
            event_type IN (
                "similar_carousel_viewed",
                "similar_carousel_viewed_native"
            )
            AND MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
            AND YEAR(ts_client_event) = year
            AND MONTH(ts_client_event) = month
            AND DAY(ts_client_event) = day
    ),

    carousel_recommendation_enriched AS (
        SELECT
            carousel_recommendation_delivered.*,
            yp_recs_logs.display_type,
            yp_recs_logs.experiments,
            yp_recs_logs.experiments_variants,
            DENSE_RANK() OVER (
                PARTITION BY
                    yp_recs_logs.id_user,
                    yp_recs_logs.business_context,
                    yp_recs_logs.display_type
                ORDER BY
                    yp_recs_logs.ts_log
            ) AS log_index
        FROM carousel_recommendation_delivered
        /*
        TODO: once we have a recset identifier, we can perform a better join
        directly by the recset_id, instead of performing the temporal join
        */
        INNER JOIN
            yellow_pages_recommendation_logs AS yp_recs_logs
          ON
            carousel_recommendation_delivered.id_user = yp_recs_logs.id_user
            AND carousel_recommendation_delivered.business_context = yp_recs_logs.business_context
            AND carousel_recommendation_delivered.ts_rec_created >= yp_recs_logs.ts_log
    )

    SELECT * FROM carousel_recommendation_enriched WHERE log_index = 1
),


email_recommendations as (

    WITH email_recommendation_delivered AS (
        /* This CTE takes event data from Braze */
        WITH emails_sent AS (
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
                        LOWER(campaign_name) LIKE "%rent%" THEN "rent"
                    WHEN LOWER(campaign_name) LIKE "%sale%" THEN "sale"
                END AS business_context,
                DATE(ts_email_sent) AS dt_email_sent,
                CASE WHEN ts_email_first_opened IS NOT NULL THEN least(ts_email_first_opened, ts_email_first_clicked) END AS ts_rec_created,
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
                AND DATE(ts_email_sent) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        )

        SELECT
          id_email,
          id_user,
          display_type,
          business_context,
          dt_email_sent,
          MAX(ts_rec_created) AS ts_rec_created,
          MAX(ts_rec_received) AS ts_rec_received
        FROM emails_sent
        GROUP BY id_email, id_user, display_type, business_context, dt_email_sent
    ), -- end email_recommendation_delivered

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
            AND MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
        GROUP BY id_user, id_session
    ), -- end email_user_sessions

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
    ), -- end email_closest_session

    yellow_pages_recommendation_logs_dedup AS (
        /*
        ensure we only have one log yellow-pages log per:
        user, business_context, display_type and dt_log
        */
        WITH duplicated_yellow_pages_recommendations_logs AS (
            SELECT
                *,
                DENSE_RANK() OVER (PARTITION BY id_user, business_context, display_type, dt_log ORDER BY ts_log) AS log_index
            FROM yellow_pages_recommendation_logs
        )

        SELECT
            id_user,
            business_context,
            display_type,
            id_anchors,
            similar_listings,
            experiments,
            experiments_variants,
            ts_log,
            dt_log
        FROM duplicated_yellow_pages_recommendations_logs
        WHERE log_index = 1 AND display_type != "not_provided"
    ) -- end yellow_pages_recommendation_logs_dedup

    SELECT
        yp_recs_logs.id_user,
        yp_recs_logs.id_anchors,
        email_delivered.ts_rec_created,
        email_delivered.ts_rec_received,
        email_delivered.display_type,
        email_delivered.business_context,
        "house" AS type_item,
        email_closest_session.country,
        email_closest_session.region,
        email_closest_session.city,
        email_closest_session.device_family,
        email_closest_session.platform,
        email_closest_session.language,
        POSEXPLODE(yp_recs_logs.similar_listings) AS (item_rank, id_item),
        -- TODO: review this id_subjects assignment
        CASE
            WHEN
                email_delivered.business_context = "sale"
                THEN yp_recs_logs.id_anchors
            WHEN
                email_delivered.business_context = "rent"
                THEN CAST(ARRAY(yp_recs_logs.id_user) AS ARRAY <INT>)
        END AS id_subjects,
        -- TODO: type_subject and ml_model should come from YP recs logs
        "user" AS type_subject,
        "house-user-embeddings" ml_model,
        yp_recs_logs.experiments,
        yp_recs_logs.experiments_variants,
        YEAR(email_delivered.ts_rec_created) AS year,
        MONTH(email_delivered.ts_rec_created) AS month,
        DAY(email_delivered.ts_rec_created) AS day
    FROM email_recommendation_delivered AS email_delivered
    LEFT JOIN email_closest_session ON
        email_delivered.id_email = email_closest_session.id_email
    /*
    inner join with yellow-pages logs. If, for some reason, yellow-pages logs
    are not available we will lose track of the emails for that day
    */
    INNER JOIN
        yellow_pages_recommendation_logs_dedup AS yp_recs_logs ON
        email_delivered.id_user = yp_recs_logs.id_user
        AND email_delivered.business_context = yp_recs_logs.business_context
        AND email_delivered.display_type = yp_recs_logs.display_type
        AND email_delivered.dt_email_sent = yp_recs_logs.dt_log
),


recommendations AS (
    SELECT
        id_user,
        id_item,
        id_subjects,
        id_anchors,
        ts_rec_created,
        ts_rec_received,
        DATE(ts_rec_received) AS dt_rec_received,
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
        experiments,
        experiments_variants
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
        DATE(ts_rec_received) AS dt_rec_received,
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
        experiments,
        experiments_variants
    FROM email_recommendations
)

SELECT
    SHA2(
        CONCAT(
            recommendations.id_user,
            concat_ws(',', recommendations.id_subjects),
            concat_ws(',', recommendations.id_anchors),
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
            concat_ws(',', recommendations.id_subjects),
            concat_ws(',', recommendations.id_anchors),
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
    AND recommendations.business_context IS NOT NULL
