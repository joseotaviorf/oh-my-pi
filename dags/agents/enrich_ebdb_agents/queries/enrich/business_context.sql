WITH agent_data_business_contexts_served AS (
    SELECT
        adbcsa.id_agent_data AS id_agent,
        adbcsa.rev_type,
        adbcsa.business_context,
        ROW_NUMBER() OVER (PARTITION BY adbcsa.id_agent_data ORDER BY ure.ts_revision DESC) = 1 AS is_last_updated,
        DATE(ure.ts_revision) AS dt_started,
        DATE(
            CASE
                WHEN ROW_NUMBER() OVER (PARTITION BY adbcsa.id_agent_data ORDER BY ure.ts_revision DESC) = 1
                    THEN LEAD(ure.ts_revision) OVER (PARTITION BY adbcsa.id_agent_data ORDER BY ure.ts_revision)
                ELSE LEAD(ure.ts_revision) OVER (PARTITION BY adbcsa.id_agent_data ORDER BY ure.ts_revision) - INTERVAL 1 DAY
            END 
        ) AS dt_ended
    FROM
        datalake_ebdb_clean.agent_data_business_contexts_served_aud AS adbcsa
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ure.id = adbcsa.rev
),
agent_history_business_context AS (
    SELECT
        adbcs.id_agent,
        adbcs.business_context,
        DATE(MIN(adbcs.dt_started)) AS dt_started,
        DATE(
            CASE
                WHEN MAX(adbcs.is_last_updated) = TRUE OR MAX(adbcs.dt_ended) IS NULL THEN NOW()
                ELSE MAX(adbcs.dt_ended)
            END
        ) AS dt_ended
    FROM
        agent_data_business_contexts_served AS adbcs
    GROUP BY ALL
),
agent_daily_business_context AS (
    SELECT
        adbcs.id_agent,
        adbcs.business_context,
        ad.date
    FROM
        agent_history_business_context AS adbcs
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN adbcs.dt_started AND adbcs.dt_ended 
    GROUP BY ALL
),
agent_data AS (
    SELECT
        ada.id AS id_agent,
        u.id AS id_user,
        ada.rev_type,
        ada.agent_type,
        ada.is_active,
        ROW_NUMBER() OVER (PARTITION BY ada.id ORDER BY ure.ts_revision DESC) = 1 AS is_last_updated,
        ure.ts_revision AS ts_started,
        LEAD(ure.ts_revision) OVER (PARTITION BY ada.id ORDER BY ure.ts_revision) AS ts_ended
    FROM
        datalake_ebdb_clean.agent_data_aud AS ada
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ure.id = ada.rev
    LEFT JOIN 
        datalake_ebdb_user.user AS u
            ON u.id_agent = ada.id
    ORDER BY ure.ts_revision
),
agent_data_history AS (
    SELECT
        ad.id_agent,
        ad.id_user,
        FIRST(ad.agent_type) FILTER(WHERE agent_type IS NOT NULL) AS agent_type,
        IF(
            MAX(ad.is_last_updated) IS TRUE,
            LAST(ad.is_active) FILTER(WHERE is_active IS NOT NULL),
            FALSE
        ) AS is_active,
        DATE(MIN(ad.ts_started)) AS dt_started,
        DATE(
            CASE
                WHEN MIN(ad.is_active) FILTER(WHERE is_active IS NOT NULL) = FALSE 
                    AND MAX(ad.ts_ended) IS NULL 
                    THEN MAX(ad.ts_started)              
                ELSE MAX(ad.ts_ended) - INTERVAL 1 DAY
            END
        ) AS dt_ended
    FROM
        agent_data AS ad
    GROUP BY ALL
)
SELECT 
    adh.id_agent,
    adh.id_user,
    adh.agent_type,
    CASE
        WHEN adh.agent_type = 'CORRETOR_5A' AND adbc.business_context IS NULL THEN 'RENT'
        WHEN adh.agent_type = 'CORRETOR_REDE' AND adbc.business_context IS NULL THEN 'REDE'
        WHEN adbc.business_context = 'SALE_PRIMARY_MARKET' THEN 'SALE'
        ELSE adbc.business_context
    END AS business_context,
    adh.is_active,
    COALESCE(MIN(adbc.date), MIN(adh.dt_started)) AS dt_started,
    COALESCE(MAX(adbc.date), MAX(adh.dt_ended)) AS dt_ended
FROM
    agent_data_history AS adh
LEFT JOIN 
    agent_daily_business_context AS adbc
        ON adbc.id_agent = adh.id_agent
        AND adbc.date BETWEEN adh.dt_started AND adh.dt_ended
WHERE
    COALESCE(adh.agent_type, adbc.business_context) IS NOT NULL
GROUP BY ALL