-- Latest online Payin evaluator scores per Matthew WhatsApp Langfuse session.
-- Scores can arrive hours after the chatbot session watermark, so this table is
-- incremental on scores.ts_created and only emits sessions that were judged.
WITH payin_scores_ranked AS (
    SELECT
        s.id_session AS id_langfuse_session,
        s.name AS score_name,
        CAST(CAST(s.value AS DOUBLE) AS INT) AS numeric_value,
        s.string_value,
        CAST(s.ts_created AS TIMESTAMP) AS ts_score_created,
        ROW_NUMBER() OVER (
            PARTITION BY s.id_session, s.name
            ORDER BY CAST(s.ts_created AS TIMESTAMP) DESC
        ) AS rn
    FROM
        datalake_langfuse_clean.scores AS s
    INNER JOIN
        datalake_chatbot.sessions AS chatbot_sessions
            ON chatbot_sessions.id_langfuse_session = s.id_session
            AND chatbot_sessions.bot = 'matthew'
    WHERE
        MAKE_DATE(s.year, s.month, s.day) >= DATE('{load_start_date}') - INTERVAL 2 DAY
        AND CAST(s.ts_created AS TIMESTAMP) >= TIMESTAMP('{load_start_date}') - INTERVAL 2 DAY
        AND s.name IN (
            'PayinResolutionEvaluator',
            'PayinFailureDiagnosisEval',
            'PayinFrustrationEval'
        )
        AND s.id_session IS NOT NULL
)
SELECT
    id_langfuse_session,
    MAX(CASE WHEN score_name = 'PayinResolutionEvaluator' THEN numeric_value END) AS eval_payin_resolution,
    MAX(CASE WHEN score_name = 'PayinFailureDiagnosisEval' THEN string_value END) AS eval_payin_failure_diagnosis,
    MAX(CASE WHEN score_name = 'PayinFrustrationEval' THEN string_value END) AS eval_payin_frustration,
    MAX(ts_score_created) AS ts_last_eval_created,
    YEAR(MAX(ts_score_created)) AS year,
    MONTH(MAX(ts_score_created)) AS month,
    DAYOFMONTH(MAX(ts_score_created)) AS day
FROM
    payin_scores_ranked
WHERE
    rn = 1
GROUP BY
    id_langfuse_session
