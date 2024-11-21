SELECT
    cs.sk_company,
    cs.id_hubspot,
    ce.uuid_company,
    COALESCE(ce.company_name, c.name, cs.extracted_3p_tag, 'Unknown') AS company_name,
    COALESCE(ce.trade_name, 'Unknown') AS trade_name,
    COALESCE(c.name, 'Unknown') AS hubspot_company_name,
    COALESCE(c.tag_real_estate_agency, cs.extracted_3p_tag, 'Unknown') AS tag,
    COALESCE(c.extracted_3p_tag, cs.extracted_3p_tag, ce.trade_name, 'Unknown') AS extracted_3p_tag,
    COALESCE(ce.status, 'Unknown') AS company_domain_status,
    COALESCE(c.lead_status, 'Unknown') AS lead_status,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    COALESCE(c.sale_lead_status, 'Unknown') AS sale_lead_status,
    COALESCE(c.rent_lead_status, 'Unknown') AS rent_lead_status,
    CASE
        WHEN (
            (cs.is_3p_bh IS NOT NULL AND cs.is_3p_bh)
            OR ce.state_abbreviation IS NOT DISTINCT FROM 'MG'
            OR c.state IS NOT DISTINCT FROM 'MG'
            OR COALESCE(UPPER(c.tag_real_estate_agency) LIKE '%[3PBH-%]%', FALSE)
        )
            THEN '3P BH'
        ELSE '3P 5A'
    END AS product,
    COALESCE(c.member_category, 'Unknown') AS member_category,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, member_category will be deprecated and we will remove the row above
    COALESCE(c.sale_member_category, 'Unknown') AS sale_member_category,
    COALESCE(c.rent_member_category, 'Unknown') AS rent_member_category,
    COALESCE(c.company_cluster, 'Unknown') as company_cluster,
    COALESCE(c.member_type, 'Unknown') AS member_type,
    COALESCE(ce.public_area, c.address, 'Unknown') AS address,
    COALESCE(ce.zip_code, c.zip_code, 'Unknown') AS zip_code,
    COALESCE(ce.city, TRIM(UPPER(c.city)), 'Unknown') AS city,
    COALESCE(ce.state_abbreviation, c.state, 'Unknown') AS state_abbreviation,
    COALESCE(ce.state, s.name, c.state, 'Unknown') AS state,
    COALESCE(IF(ce.country = 'Brasil', 'Brazil', ce.country), c.country, 'Unknown') AS country,
    COALESCE(c.country_code, 'Undefined') AS country_code,
    COALESCE(c.domain, 'Unknown') AS domain,
    COALESCE(c.e_mail, 'Unknown') AS e_mail,
    COALESCE(c.phone, 'Unknown') AS phone,
    COALESCE(c.partnership_type, 'Unknown') AS partnership_type,
    COALESCE(c.crm, 'Unknown') AS crm,
    COALESCE(ce.document, c.document, 'Unknown') AS document,
    COALESCE(ce.cnpj, c.cnpj, 'Unknown') AS cnpj,
    COALESCE(ce.rfc, c.rfc, 'Unknown') AS rfc,
    COALESCE(c.creci, 'Unknown') AS creci,
    COALESCE(c.cluster_performance, 'Unknown') AS cluster_performance,
    COALESCE(c.responsible_secretary, 'Unknown') AS responsible_secretary,
    COALESCE(c.responsible_supply_expert, 'Unknown') AS responsible_supply_expert,
    COALESCE(c.responsible_demand_expert, 'Unknown') AS responsible_demand_expert,
    COALESCE(c.responsible_operations_supply, 'Unknown') AS responsible_operations_supply,
    COALESCE(o.first_name||' '|| o.last_name, 'Unknown') AS account_manager,
    CASE
        WHEN c.is_juridical_person THEN 'PJ'
        WHEN c.is_natural_person THEN 'PF'
        ELSE 'Unknown'
    END AS person_type,
    (
        COALESCE(c.sale_lead_status IN ('Parceiro', 'Membro', 'Em processo tombamento'), FALSE)
        OR COALESCE(c.rent_lead_status IN ('Parceiro', 'Membro', 'Em processo tombamento'), FALSE)
    ) AS is_partner,
    COALESCE(c.sale_lead_status IN ('Parceiro', 'Membro', 'Em processo tombamento'), FALSE) AS is_sale_partner,
    COALESCE(c.rent_lead_status IN ('Parceiro', 'Membro', 'Em processo tombamento'), FALSE) AS is_rent_partner,
    (
        (cs.is_3p_bh IS NOT NULL AND cs.is_3p_bh)
        OR ce.state_abbreviation IS NOT DISTINCT FROM 'MG'
        OR c.state IS NOT DISTINCT FROM 'MG'
        OR COALESCE(UPPER(c.tag_real_estate_agency) LIKE '%[3PBH-%]%', FALSE)
    ) AS is_3p_bh,
    (
        (cs.is_3p_bh IS NULL OR NOT cs.is_3p_bh)
        AND ce.state_abbreviation IS DISTINCT FROM 'MG'
        AND c.state IS DISTINCT FROM 'MG'
        AND COALESCE(UPPER(c.tag_real_estate_agency) NOT LIKE '%[3PBH-%]%', TRUE)
    ) AS is_3p_5a,
    COALESCE(c.is_for_sale, FALSE) OR COALESCE(ce.sale_listings_currently_owned, 0) > 0 AS is_for_sale,
    COALESCE(c.is_for_rent, FALSE) OR COALESCE(ce.rent_listings_currently_owned, 0) > 0 AS is_for_rent,
    c.is_flagged_as_leadgen AS is_flagged_as_leadgen_in_hubspot,
    COALESCE(c.is_archived, FALSE) AS is_archived,
    c.ts_archived,
    LEAST(c.ts_created, ce.ts_created) AS ts_created,
    GREATEST(c.ts_updated, ce.ts_updated) AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_rede_company.company_sks AS cs
LEFT JOIN
    datalake_hubspot.company AS c
        ON c.id_company = cs.id_hubspot
LEFT JOIN
    datalake_company.company AS ce
        ON ce.uuid_company = cs.uuid_company
LEFT JOIN
    datalake_ebdb_clean.state AS s
        ON s.abbreviation = c.state
LEFT JOIN
    datalake_hubspot.owner AS o
        ON c.id_hubspot_owner = o.id_owner
WHERE
    cs.has_been_member