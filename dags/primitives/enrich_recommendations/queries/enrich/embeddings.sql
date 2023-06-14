/*
All the embeddings used for recommendations. (houses and users)
The embeddings are scaled (from [-1, 1] to [0, 1]) and normalized (l2 norm) to facilitate metrics calculations.
*/

WITH embeddings_from_emlio_logs AS (
    SELECT id_service AS ml_model,
        service_version AS ml_model_version,
        LOWER(
            CASE id_service
                WHEN 'house-similarity-embeddings' THEN GET_JSON_OBJECT(service_keys, '$.model_type')
                WHEN 'house-user-embeddings' THEN SPLIT(GET_JSON_OBJECT(service_keys, '$.model_type'), "_")[0]
                END
        ) AS business_context,
        CASE id_service
            WHEN 'house-similarity-embeddings' THEN 'house'
            WHEN 'house-user-embeddings' THEN SPLIT(GET_JSON_OBJECT(service_keys, '$.model_type'), "_")[1]
            END AS type_id,
        CAST(
            (
                CASE (
                    CASE id_service
                        WHEN 'house-similarity-embeddings' THEN 'house'
                        WHEN 'house-user-embeddings' THEN SPLIT(GET_JSON_OBJECT(service_keys, '$.model_type'), "_")[1]
                        END
                )
                WHEN 'user' THEN GET_JSON_OBJECT(service_keys, '$.user_id')
                WHEN 'house' THEN GET_JSON_OBJECT(service_keys, '$.house_id')
                END
            ) AS INT
        ) AS id,
        CAST(
            SPLIT(
                REGEXP_REPLACE(outputs, '\\[|\\]|"', ""),
                ",",
                -1
            ) AS ARRAY <FLOAT>
        ) AS embedding,
        ts_log AS ts_embedding,
        year,
        month,
        day
    FROM datalake_emlio_clean.emlio_logs
    WHERE id_service IN ('house-user-embeddings', 'house-similarity-embeddings')
        AND inference_type = 'online'
        AND MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
),

dedup_embeddings_from_emlio_logs AS (
    SELECT DISTINCT *,
        (exploded_embedding + 1.0) / 2.0 AS normalized_exploded_embedding
    FROM (
        SELECT *,
            posexplode(embedding) AS (position_embedding, exploded_embedding),
            DENSE_RANK() OVER (
                PARTITION BY ml_model, business_context, type_id, id, ts_embedding
                ORDER BY ml_model_version DESC
            ) = 1 AS first_embedding
        FROM embeddings_from_emlio_logs
    )
    WHERE first_embedding
)

SELECT DISTINCT
    ml_model,
    ml_model_version,
    business_context,
    type_id,
    id,
    ts_embedding,
    ARRAY_AGG(
        normalized_exploded_embedding  / sqrt(
            SUM(POWER(normalized_exploded_embedding , 2))
            OVER (PARTITION BY ml_model, ml_model_version, business_context, type_id, id, ts_embedding)
        )
    ) OVER (
        PARTITION BY ml_model, ml_model_version, business_context, type_id, id, ts_embedding
        ORDER BY position_embedding
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS embedding,
    year,
    month,
    day
FROM dedup_embeddings_from_emlio_logs
