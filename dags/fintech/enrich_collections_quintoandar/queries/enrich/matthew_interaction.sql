WITH mathew_session AS (
    SELECT
    DISTINCT
        s.id_session AS score_session,
        ss.id_session,
        ss.id_user,
        ss.ts_created
    FROM
        datalake_chatbot.sessions ss
    LEFT JOIN
        datalake_langfuse_clean.scores s
        ON s.id_langfuse_session = ss.id_external
    WHERE
        name = 'SessionContainsMatthewAgentEvaluator'
        AND value = 1
),
ebdb AS (
    SELECT
    DISTINCT
        fc.id_contract AS id,
        fc.id_user,
        ebdb.dt_started
    FROM
        datalake_ebdb_contract.contract_person fc
    LEFT JOIN
        datalake_ebdb_clean.contract ebdb
        ON ebdb.id = fc.id_contract
    WHERE
        fc.id_user > 0
        AND ebdb.status = 'Ativo'
        AND fc.contract_role IN ('tenant','dweller')
    UNION ALL
    SELECT
    DISTINCT
        id,
        id_user,
        dt_started
    FROM
        datalake_ebdb_clean.contract
    WHERE
        status = 'Ativo'
)
SELECT
    DISTINCT
    bs.score_session,
    bs.id_session,
    bs.id_user,
    ebdb.id AS id_contract,
    bs.ts_created
FROM
    mathew_session AS bs
LEFT JOIN ebdb
    ON bs.id_user = ebdb.id_user
    AND DATE(bs.ts_created) >= DATE(ebdb.dt_started)
