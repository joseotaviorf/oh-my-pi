WITH updated_company_product AS (
    SELECT
        mp.uuid_person
    FROM
        datalake_company_clean.member_profile AS mp
    WHERE
        DATE(mp.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        a.uuid_person
    FROM
        datalake_ebdb_agent_events.agent_unified_identity AS a
    WHERE
        DATE(a.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
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
    COALESCE(mp.status = 'ACTIVE' AND cp.deactivation_reason IS NULL, FALSE) AS is_active,
    p.id IN (1, 32, 29) AS is_legacy_product,
    p.id NOT IN (1, 32, 29, 40) AS is_valid_product,
    ROW_NUMBER() OVER(PARTITION BY a.id_unified_agent ORDER BY p.id NOT IN (1, 32, 29, 40) DESC, IF(mp.status = 'ACTIVE', 1, 0) DESC, a.ts_updated DESC) = 1 AS is_lastest_valid,
    mp.ts_created AS ts_started,
    CASE
        WHEN cp.status = 'INACTIVE' THEN cp.ts_database_transaction
        WHEN mp.status = 'INACTIVE' THEN mp.ts_updated
    END AS ts_ended,
    GREATEST(mp.ts_updated, a.ts_updated) AS ts_updated
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
