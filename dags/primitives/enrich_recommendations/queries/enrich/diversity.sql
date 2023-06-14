WITH base AS (
    SELECT DISTINCT
        dt_rec_received,
        id_recset
    FROM
        datalake_recommendations.recommendation AS recommendation
        WHERE recommendation.dt_rec_received
            BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
),

rec_embedding AS (
    SELECT DISTINCT
        id_recset,
        id_rec,
        item_rank,
        embedding
    FROM (
        SELECT
            recommendation.id_recset,
            recommendation.id_rec,
            recommendation.item_rank,
            embeddings.embedding,
            rank() OVER (PARTITION BY recommendation.id_rec ORDER BY embeddings.ts_embedding DESC, embeddings.embedding) = 1 AS latest_embedding
        FROM
            datalake_recommendations.recommendation AS recommendation
        LEFT JOIN
            datalake_recommendations.embeddings AS embeddings
            ON recommendation.business_context = embeddings.business_context
            AND recommendation.ml_model = embeddings.ml_model
            AND recommendation.id_item = embeddings.id
            AND recommendation.ts_rec_created >= embeddings.ts_embedding
        WHERE
            embeddings.type_id = 'house'
            AND embeddings.embedding is not NULL
            AND recommendation.dt_rec_received
                BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
            AND MAKE_DATE(embeddings.year, embeddings.month, embeddings.day)
                BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    )
    WHERE
        latest_embedding
),

cross_embeddings AS (
    SELECT
        rec_embedding_1.id_recset,
        rec_embedding_1.item_rank AS item_rank_1,
        rec_embedding_2.item_rank AS item_rank_2,
        rec_embedding_1.embedding AS embedding_1,
        rec_embedding_2.embedding AS embedding_2
    FROM
        rec_embedding AS rec_embedding_1
    INNER JOIN
        rec_embedding AS rec_embedding_2
        ON rec_embedding_1.id_recset = rec_embedding_2.id_recset
        AND rec_embedding_1.item_rank < rec_embedding_2.item_rank
),

explode_embeddings AS (
    SELECT
        id_recset,
        item_rank_1,
        item_rank_2,
        EXPLODE(ARRAYS_ZIP(embedding_1, embedding_2)) AS zip_embedding
    FROM
        cross_embeddings
),

cos_similarity AS (
    SELECT
        id_recset,
        item_rank_1,
        item_rank_2,
        SUM(COALESCE(zip_embedding['embedding_1']) * COALESCE(zip_embedding['embedding_2'])) AS cos_similarity
    FROM
        explode_embeddings
    GROUP BY id_recset,
        item_rank_1,
        item_rank_2
),

diversity_at_3 AS (
    SELECT
        id_recset,
        1 - MEAN(cos_similarity) AS diversity_at_3
    FROM
        cos_similarity
    WHERE
        item_rank_1 <= 3 AND item_rank_2 <= 3
    GROUP BY
        id_recset
),

diversity_at_5 AS (
    SELECT
        id_recset,
        1 - MEAN(cos_similarity) AS diversity_at_5
    FROM
        cos_similarity
    WHERE
        item_rank_1 <= 5
        AND item_rank_2 <= 5
    GROUP BY
        id_recset
),

diversity_at_10 AS (
    SELECT
        id_recset,
        1 - MEAN(cos_similarity) AS diversity_at_10
    FROM cos_similarity
    WHERE
        item_rank_1 <= 10
        AND item_rank_2 <= 10
    GROUP BY id_recset
)

SELECT
    base.id_recset,
    COALESCE(diversity_at_3, 0) AS diversity_at_3,
    COALESCE(diversity_at_5, 0) AS diversity_at_5,
    COALESCE(diversity_at_10, 0) AS diversity_at_10,
    base.dt_rec_received
FROM
    base
LEFT JOIN diversity_at_3
  ON base.id_recset = diversity_at_3.id_recset
LEFT JOIN diversity_at_5
  ON base.id_recset = diversity_at_5.id_recset
LEFT JOIN diversity_at_10
  ON base.id_recset = diversity_at_10.id_recset
