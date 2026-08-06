WITH agent_company_product AS (
    SELECT
        a.id_unified_agent,
        a.uuid_person,
        c.id AS id_company,
        p.id AS id_product,
        p.name AS product_name,
        p.id IN (1, 32, 29) AS is_legacy_product,
        ROW_NUMBER() OVER(PARTITION BY a.id_unified_agent, p.id, mp.updated_at ORDER BY mp.updated_at DESC) = 1 AS dedup_product,
        mp.updated_at AS ts_updated
    FROM
        datalake_agent.agent_unified_identity AS a
    JOIN
        datalake_company_clean.company AS c
            ON c.uuid_company = a.uuid_company
    JOIN
        datalake_company_transactional.member_profile AS mp
            ON mp.company_product_company_id = c.id
            AND mp.person_uuid = a.uuid_person
    JOIN
        datalake_company_clean.product AS p
            ON p.id = mp.company_product_product_id
    WHERE
        p.id NOT IN (40) -- the "Alias" product is not a valid product for Agent profile purpose
        AND (
            DATE(mp.updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
            OR DATE(a.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        )
),
legacy_product_limit AS (
    SELECT
        a.id_unified_agent,
        a.id_company,
        a.id_product,
        a.uuid_person,
        a.product_name,
        a.is_legacy_product,
        a.ts_updated,
        IF(
            a.is_legacy_product,
            FIRST_VALUE(a.ts_updated) OVER(
            PARTITION BY 
                a.id_unified_agent
                ORDER BY 
                    IF(a.is_legacy_product, 1, 0) ASC,
                    a.ts_updated ASC
            ),
            NULL
        ) AS ts_legacy_product_limit
    FROM
        agent_company_product AS a
    WHERE
        dedup_product IS TRUE
),
mod_product AS (
    SELECT
        a.id_unified_agent,
        a.id_company,
        a.id_product,
        a.uuid_person,
        LAG(a.id_product) OVER(PARTITION BY a.id_unified_agent ORDER BY a.ts_updated) AS previous_id_product,
        a.product_name,
        a.is_legacy_product,
        a.ts_updated
    FROM
        legacy_product_limit AS a
    WHERE
        a.is_legacy_product IS FALSE
        OR a.ts_updated < a.ts_legacy_product_limit
),
company_product AS (
    SELECT
        a.id_unified_agent,
        a.id_company,
        a.id_product,
        a.uuid_person,
        a.product_name,
        cp.deactivation_reason,
        cp.deactivation_sub_reason,
        a.is_legacy_product,
        cp.status = 'ACTIVE' AS is_active,
        ROW_NUMBER() OVER(PARTITION BY a.id_unified_agent ORDER BY IF(cp.status = 'ACTIVE', 1, 0) DESC, a.ts_updated DESC) = 1 AS is_lastest,
        ROW_NUMBER() OVER(PARTITION BY a.id_unified_agent, DATE(a.ts_updated) ORDER BY a.ts_updated DESC) = 1 AS is_lastest_by_date,
        a.ts_updated,
        cp.ts_database_transaction AS ts_company_product_updated
    FROM
        mod_product AS a
    JOIN
        datalake_company_clean.company_product AS cp
            ON cp.id_company = a.id_company
            AND cp.id_product = a.id_product
    WHERE
        COALESCE(a.previous_id_product, -1) <> a.id_product
)
SELECT
    XXHASH64(a.id_unified_agent, a.id_company, a.id_product, a.ts_updated) AS id_agent_product,
    a.id_unified_agent,
    a.id_company,
    a.id_product,
    a.uuid_person,
    a.product_name,
    CASE
        WHEN a.is_legacy_product IS TRUE AND a.deactivation_reason IS NULL 
            THEN 'MANUALLY_DEACTIVATED_LEGACY_PRODUCT'
        ELSE a.deactivation_reason
    END AS deactivation_reason,
    a.deactivation_sub_reason,
    IF(a.is_legacy_product, FALSE, a.is_active) AS is_active,
    a.is_lastest,
    a.is_lastest_by_date,
    a.is_legacy_product,
    DATE(a.ts_updated) AS dt_updated,
    a.ts_updated AS ts_started,
    CASE
      WHEN a.is_active IS FALSE AND a.is_lastest IS TRUE THEN a.ts_company_product_updated
      WHEN a.is_lastest_by_date IS FALSE THEN LEAD(a.ts_updated) OVER(PARTITION BY a.id_unified_agent ORDER BY a.ts_updated) - INTERVAL 1 SECOND
      ELSE LEAD(a.ts_updated) OVER(PARTITION BY a.id_unified_agent ORDER BY a.ts_updated) - INTERVAL 1 DAY
    END AS ts_ended
FROM
    company_product AS a