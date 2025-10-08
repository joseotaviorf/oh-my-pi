WITH mathew_session AS (
    SELECT
    DISTINCT
        s.id_session AS score_session,
        ss.id_session,
        ss.id_user,
        ss.ts_created,
        ss.ts_finished
    FROM
        datalake_chatbot.support_sessions ss
    LEFT JOIN
        datalake_langfuse_clean.scores s
        ON s.id_session = ss.id_external
    WHERE
        name = 'SessionContainsMatthewAgentEvaluator'
        AND value = 1
),
dim_user_contract AS (

)
SELECT
    DISTINCT
    bs.score_session,
    bs.id_session,
    bs.id_user,
    du.contracts,
    bs.ts_created
FROM
    mathew_session AS bs
LEFT JOIN dim_user_wallet_timeline AS du
    ON bs.id_user = du.sk_user
    AND DATE(bs.ts_created) >= DATE(du.dt_reference)
