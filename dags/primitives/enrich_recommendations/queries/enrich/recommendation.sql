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
        ts_client_event AS ts_rec_created,
        ts_client_event AS ts_rec_received,
        year,
        month,
        day,
        COALESCE(id_user, id_amplitude) AS id_user,
        ARRAY(
            CAST(GET_JSON_OBJECT(event_properties, "$.house_id") AS INT)
        ) AS id_subjects,
        GET_JSON_OBJECT(
            event_properties, "$.business_context"
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
        AND YEAR(ts_client_event) = year
        AND MONTH(ts_client_event) = month
        AND DAY(ts_client_event) = day
)


SELECT
    id_user,
    id_item,
    id_subjects,
    id_anchors,
    SHA2(
        CONCAT(
            id_user, id_item, ts_rec_created, business_context, display_type
        ),
        256
    ) AS id_rec,
    SHA2(
        CONCAT(id_user, ts_rec_created, business_context, display_type), 256
    ) AS id_recset,
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
    item_rank + 1 AS item_rank,
    ts_rec_created,
    ts_rec_received,
    year,
    month,
    day
FROM
    carousel_recommendations
WHERE
    id_item IS NOT NULL
    AND id_subjects IS NOT NULL
    AND id_anchors IS NOT NULL
    AND business_context IS NOT NULL

/* TODO: email recommendations from Braze */
