WITH updated_company_product AS (
    SELECT
        mp.uuid_person
    FROM
        datalake_company_clean.member_profile AS mp
    JOIN
        datalake_company_clean.company_product AS cp
            ON cp.id_company = mp.id_company
            AND cp.id_product = mp.id_product
    WHERE
        DATE(mp.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        OR DATE(cp.ts_database_transaction) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        a.uuid_person
    FROM
        datalake_ebdb_agent_events.agent_unified_identity AS a
    WHERE
        DATE(a.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
agent_product AS (
    SELECT
        XXHASH64(a.id_unified_agent, c.id, p.id, mp.ts_created) AS id_agent_product,
        a.id_unified_agent,
        a.id_agent,
        a.uuid_person,
        a.uuid_company,
        p.id AS id_product,
        p.name AS product_name,
        cp.deactivation_reason,
        cp.deactivation_sub_reason,
        COALESCE(
            mp.status = 'ACTIVE' 
            AND cp.deactivation_reason IS NULL
            AND cp.status = 'ACTIVE'
        , FALSE) AS is_active,
        p.id IN (1, 32, 29) AS is_legacy_product,
        p.id NOT IN (1, 32, 29, 40) AS is_valid_product,
        mp.ts_created AS ts_started,
        CASE
            WHEN cp.deactivation_reason IS NOT NULL OR cp.status = 'INACTIVE' THEN cp.ts_database_transaction
            WHEN mp.status = 'INACTIVE' THEN mp.ts_updated
        END AS ts_ended,
        GREATEST(mp.ts_updated, a.ts_updated, cp.ts_database_transaction) AS ts_updated
    FROM
        updated_company_product AS lastest_updated
    JOIN
        datalake_ebdb_agent_events.agent_unified_identity AS a
            ON a.uuid_person = lastest_updated.uuid_person
    JOIN
        datalake_company_clean.company AS c
            ON c.uuid_company = a.uuid_company
    JOIN
        datalake_company_clean.member_profile AS mp
            ON mp.id_company = c.id
            AND mp.uuid_person = a.uuid_person
    JOIN
        datalake_company_clean.product AS p
            ON p.id = mp.id_product
    JOIN
        datalake_company_clean.company_product AS cp
            ON cp.id_company = c.id
            AND cp.id_product = mp.id_product
)
SELECT
    ap.id_agent_product,
    ap.id_unified_agent,
    ap.id_agent,
    ap.uuid_person,
    ap.uuid_company,
    ap.id_product,
    ap.product_name,
    ap.deactivation_reason,
    ap.deactivation_sub_reason,
    ap.is_active,
    ap.is_legacy_product,
    ap.is_valid_product,
    ROW_NUMBER() OVER(
        PARTITION BY
            ap.id_unified_agent
        ORDER BY 
            ap.is_valid_product DESC, 
            ap.is_active DESC, 
            ap.ts_updated DESC
    ) = 1 AS is_lastest,
    ROW_NUMBER() OVER(
        PARTITION BY 
            ap.id_unified_agent, 
            DATE(ap.ts_started)
        ORDER BY 
            ap.is_valid_product DESC, 
            ap.is_active DESC, 
            ap.ts_updated DESC
    ) = 1 AS is_lastest_by_date,
    ap.ts_started,
    ap.ts_ended,
    ap.ts_updated
FROM
    agent_product AS ap
