WITH revenue_share_updated AS (
    SELECT 
        id_revenue_share 
    FROM 
        datalake_big_agent_clean.revenue_share_invalidations 
    WHERE 
        DATE(ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT 
        id AS id_revenue_share 
    FROM 
        datalake_big_agent_clean.revenue_share
    WHERE 
        DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
revenue_share_condition AS (
    SELECT
        updated.id_revenue_share,
        MAX(IF(condition.condition_type = 'PROPERTY_CITY_REGION_ID', TRY_CAST(condition.value AS BIGINT), NULL)) AS id_region,
        MAX(IF(condition.condition_type = 'MIN_BASE_AMOUNT', TRY_CAST(condition.value AS DOUBLE), NULL)) AS minimum_base_amount,
        MAX(IF(condition.condition_type = 'MAX_BASE_AMOUNT', TRY_CAST(condition.value AS DOUBLE), NULL)) AS maximum_base_amount,
        MAX(IF(condition.condition_type = 'CRCC', TRY_CAST(condition.value AS BOOLEAN), FALSE)) AS is_crcc,
        MAX(IF(condition.condition_type = 'FIFTY', TRY_CAST(condition.value AS BOOLEAN), FALSE)) AS is_fifty
    FROM
        revenue_share_updated AS updated
    JOIN
        datalake_big_agent_clean.revenue_share_condition AS condition
            ON condition.id_revenue_share = updated.id_revenue_share
    GROUP BY 1
)
SELECT
    updated.id_revenue_share,
    invalid.id_replaced_by AS id_replacement_revenue_share,
    COALESCE(
        rs.id_invalidated_by,
        GET_JSON_OBJECT(invalid.author, "$.id")
    ) AS id_invalidation_author,
    IF(rs.relation_type = 'TIER', rs.id_relation, NULL) AS id_tier,
    COALESCE(
        IF(rs.relation_type = 'INCENTIVE_ENGINE', rs.id_relation, NULL),
        tier.id_incentive_engine
    ) AS id_incentive_engine,
    condition.id_region,
    GET_JSON_OBJECT(rs.author, "$.id") AS id_author,
    GET_JSON_OBJECT(rs.author, "$.role") AS author_role,
    rs.relation_type,
    CASE
        WHEN rs.relation_type = "TIER" THEN rs.relation_type
        WHEN rs.relation_type IN ("INCENTIVE_ENGINE", "INCENTIVE_SYSTEM_CONFIGURATION") 
            AND rs.type IS NOT NULL
            THEN rs.type
        WHEN rs.relation_type IN ("INCENTIVE_ENGINE", "INCENTIVE_SYSTEM_CONFIGURATION") 
            AND rs.type IS NULL
            AND condition.is_crcc IS TRUE
            THEN "CRCC"
        WHEN rs.relation_type IN ("INCENTIVE_ENGINE", "INCENTIVE_SYSTEM_CONFIGURATION") 
            AND rs.type IS NULL
            AND condition.is_fifty IS TRUE
            THEN "FIFTY"
        ELSE rs.type
    END AS revenue_share_type,
    rs.value AS revenue_share_value,
    rs.status,
    COALESCE(rs.invalidation_reason, invalid.reason) AS invalidation_reason,
    condition.minimum_base_amount,
    condition.maximum_base_amount,
    condition.is_crcc AS is_crcc_share_condition,
    condition.is_fifty AS is_fifty_share_condition,
    rs.status = 'ACTIVE' AS is_active,
    rs.status = 'INVALIDATED' AS is_invalid,
    COALESCE(GET_JSON_OBJECT(invalid.author, "$.role") = 'OPS', FALSE) AS is_invalidated_by_ops,
    rs.dt_validity_start,
    rs.dt_validity_end,
    invalid.ts_created AS ts_invalidation,
    rs.ts_created,
    rs.ts_updated,
    YEAR(rs.ts_created) AS year,
    MONTH(rs.ts_created) AS month,
    DAY(rs.ts_created) AS day
FROM
    revenue_share_updated AS updated
JOIN
    datalake_big_agent_clean.revenue_share AS rs
        ON rs.id = updated.id_revenue_share
LEFT JOIN
    datalake_big_agent_clean.revenue_share_invalidations AS invalid
        ON invalid.id_revenue_share = updated.id_revenue_share
LEFT JOIN
    revenue_share_condition AS condition
        ON condition.id_revenue_share = updated.id_revenue_share
LEFT JOIN
    datalake_big_agent_clean.tier AS tier
        ON tier.id = rs.id_relation
        AND rs.relation_type = 'TIER'
