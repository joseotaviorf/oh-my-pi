WITH starting_value AS (
    SELECT
        COALESCE(MAX(sk_company), 0) AS max_sk_company
    FROM
        datalake_rede_company.company_sks
),
partners_not_found_on_hubspot AS (
    SELECT -- 3P Houses without id_hubspot
        partner_3p_supply AS partner_not_found,
        MAX(UPPER(internal_admin_info) LIKE '%[3PBH-%]%') AS is_3p_bh
    FROM
        datalake_ebdb_listing.house
    WHERE
        id_company_hubspot IS NULL
        AND partner_3p_supply IS NOT NULL
    GROUP BY
        partner_3p_supply
    UNION ALL
    SELECT -- 3P Work contracts without id_hubspot
        3p_partner AS partner_not_found,
        FALSE AS is_3p_bh
    FROM
        datalake_ebdb_work_contract.work_contract
    WHERE
        id_company_hubspot IS NULL
        AND 3p_partner IS NOT NULL
),
total_partners AS (
    SELECT
        id_company AS id_hubspot,
        NULL AS extracted_3p_tag,
        NULL AS is_3p_bh
    FROM
        datalake_hubspot.company
    UNION ALL
    SELECT
        NULL AS id_hubspot,
        partner_not_found AS extracted_3p_tag,
        is_3p_bh
    FROM
        partners_not_found_on_hubspot
)
SELECT
    COALESCE(
        sk_company, -- Keep the sk_company if it is already defined, so it is durable
        sv.max_sk_company + MONOTONICALLY_INCREASING_ID() + 1 -- if not, use a number after the previous maximum value
    ) AS sk_company,
    tp.id_hubspot, -- Natural key
    tp.extracted_3p_tag, -- Natural key for companies not present in HubSpot
    tp.is_3p_bh
FROM
    total_partners AS tp,
    starting_value AS sv
LEFT JOIN 
    datalake_rede_company.company_sks AS cs
        ON tp.id_hubspot IS NOT DISTINCT FROM cs.id_hubspot
        AND tp.extracted_3p_tag IS NOT DISTINCT FROM cs.extracted_3p_tag