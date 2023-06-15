SELECT
    cs.sk_company,
    cs.id_hubspot,
    c.uuid_company,
    COALESCE(c.name, cs.extracted_3p_tag, 'Unknown') AS company_name,
    COALESCE(c.tag_real_estate_agency, cs.extracted_3p_tag, 'Unknown') AS tag,
    COALESCE(c.extracted_3p_tag, cs.extracted_3p_tag, 'Unknown') AS extracted_3p_tag,
    COALESCE(c.lead_status, 'Unknown') AS lead_status,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    COALESCE(c.sale_lead_status, 'Unknown') AS sale_lead_status,
    COALESCE(c.rent_lead_status, 'Unknown') AS rent_lead_status,
    CASE
        WHEN (
            (cs.is_3p_bh IS NOT NULL AND cs.is_3p_bh)
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
    COALESCE(c.member_type, 'Unknown') AS member_type,
    COALESCE(c.address, 'Unknown') AS address,
    COALESCE(c.zip_code, 'Unknown') AS zip_code,
    COALESCE(TRIM(UPPER(c.city)), 'Unknown') AS city,
    COALESCE(c.state, 'Unknown') AS state,
    COALESCE(c.country, 'Unknown') AS country,
    COALESCE(c.domain, 'Unknown') AS domain,
    COALESCE(c.e_mail, 'Unknown') AS e_mail,
    COALESCE(c.phone, 'Unknown') AS phone,
    COALESCE(c.partnership_type, 'Unknown') AS partnership_type,
    COALESCE(c.crm, 'Unknown') AS crm,
    COALESCE(c.cnpj, 'Unknown') AS cnpj,
    COALESCE(c.creci, 'Unknown') AS creci,
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
        OR c.state IS NOT DISTINCT FROM 'MG'
        OR COALESCE(UPPER(c.tag_real_estate_agency) LIKE '%[3PBH-%]%', FALSE)
    ) AS is_3p_bh,
    (
        (cs.is_3p_bh IS NULL OR NOT cs.is_3p_bh)
        AND c.state IS DISTINCT FROM 'MG'
        AND COALESCE(UPPER(c.tag_real_estate_agency) NOT LIKE '%[3PBH-%]%', TRUE)
    ) AS is_3p_5a,
    c.is_for_sale,
    c.is_for_rent,
    c.is_archived,
    c.ts_archived,
    c.ts_created,
    c.ts_updated,
    NOW() AS ts_load
FROM
    datalake_rede_company.company_sks AS cs
LEFT JOIN
    datalake_hubspot.company AS c
        ON c.id_company = cs.id_hubspot
WHERE
    cs.has_been_member