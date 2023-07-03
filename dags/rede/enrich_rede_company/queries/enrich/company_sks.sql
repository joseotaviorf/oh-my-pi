WITH starting_value AS (
    SELECT
        COALESCE(MAX(sk_company), 0) AS max_sk_company,
        COALESCE(MAX(sk_company_lead), 0) AS max_sk_company_lead
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
        AND uuid_company IS NULL
        AND partner_3p_supply IS NOT NULL
    GROUP BY
        partner_3p_supply
    UNION
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
        hc.id_company AS id_hubspot,
        COALESCE(hc.uuid_company, c.uuid_company) AS uuid_company,
        NULL AS extracted_3p_tag,
        NULL AS is_3p_bh,
        COALESCE(
            hc.has_been_rent_member
            OR hc.has_been_sale_member
            OR c.has_rede_product
            OR c.houses_currently_owned > 0
        , FALSE) AS has_been_member
    FROM
        datalake_hubspot.company AS hc
    FULL OUTER JOIN
        datalake_company.company AS c
            ON c.uuid_company = hc.uuid_company
    WHERE
        hc.id_company IS NOT NULL
        OR c.id_company IS NULL
        OR c.has_rede_product
        OR c.houses_currently_owned > 0
    UNION ALL
    SELECT
        NULL AS id_hubspot,
        NULL AS uuid_company,
        partner_not_found AS extracted_3p_tag,
        is_3p_bh,
        TRUE AS has_been_member
    FROM
        partners_not_found_on_hubspot
)
SELECT
    COALESCE(
        IF(NOT tp.has_been_member, -1, NULL), -- If the company is not a member, set the sk_company to -1
        NULLIF(sk_company, -1), -- Keep the sk_company if it is already defined, so it is durable
        sv.max_sk_company + MONOTONICALLY_INCREASING_ID() + 1 -- if not, use a number after the previous maximum value
    ) AS sk_company,
    COALESCE(
        sk_company_lead, -- Keep the sk_company if it is already defined, so it is durable
        sv.max_sk_company_lead + MONOTONICALLY_INCREASING_ID() + 1 -- if not, use a number after the previous maximum value
    ) AS sk_company_lead,
    tp.id_hubspot, -- Natural key (HubSpot)
    tp.uuid_company, -- Natural key (Internal Company Database)
    tp.extracted_3p_tag, -- Natural key for companies not present in HubSpot
    tp.is_3p_bh,
    tp.has_been_member
FROM
    total_partners AS tp,
    starting_value AS sv
LEFT JOIN
    datalake_rede_company.company_sks AS cs
        ON tp.id_hubspot IS NOT DISTINCT FROM cs.id_hubspot
        AND tp.uuid_company IS NOT DISTINCT FROM cs.uuid_company
        AND tp.extracted_3p_tag IS NOT DISTINCT FROM cs.extracted_3p_tag
