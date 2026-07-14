WITH partner_tier_updated AS (
    SELECT 
        id_partner_tier 
    FROM 
        datalake_big_agent_clean.partner_tier_overwritten_info 
    WHERE 
        DATE(ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT 
        id AS id_partner_tier 
    FROM 
        datalake_big_agent_clean.partner_tier
    WHERE 
        DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
overwritten_info AS (
    SELECT
        overwritten.id_partner_tier,
        overwritten.id_replaced_by,
        IF(
            GET_JSON_OBJECT(overwritten.author, "$.type") = 'PERSON', 
            GET_JSON_OBJECT(overwritten.author, "$.id"), 
            NULL
        ) AS id_author,
        GET_JSON_OBJECT(overwritten.author, "$.role") AS author_role,
        overwritten.reason,
        overwritten.ts_created
    FROM
        partner_tier_updated AS updated
    JOIN
        datalake_big_agent_clean.partner_tier_overwritten_info AS overwritten
            ON overwritten.id_partner_tier = updated.id_partner_tier
)
SELECT
    pt.id AS id_partner_tier,
    overwritten.id_replaced_by AS id_new_partner_tier,
    pt.id_tier,
    IF(pt.partner_external_type = "PERSON", pt.id_partner_external, NULL) AS uuid_person,
    IF(pt.partner_external_type = "COMPANY", pt.id_partner_external, NULL) AS uuid_company,
    overwritten.id_author AS uuid_overwritten_by,
    pt.incentive_system,
    COALESCE(pt.overwritten_reason, overwritten.reason) AS overwritten_reason,
    pt.status = 'ACTIVE' AS is_valid,
    pt.status = 'INVALIDATED' AND overwritten.id_replaced_by IS NOT NULL AS is_overwritten,
    COALESCE(overwritten.author_role = 'OPS', FALSE) AS is_overwritten_by_ops,
    pt.dt_validity_started,
    pt.dt_validity_ended,
    overwritten.ts_created AS ts_overwritten,
    pt.ts_created,
    pt.ts_updated,
    pt.year,
    pt.month,
    pt.day    
FROM
    partner_tier_updated AS updated
JOIN
    datalake_big_agent_clean.partner_tier AS pt
        ON pt.id = updated.id_partner_tier
LEFT JOIN
    overwritten_info AS overwritten
        ON overwritten.id_partner_tier = updated.id_partner_tier
