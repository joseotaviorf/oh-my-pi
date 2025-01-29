SELECT
    cs.sk_company_lead,
    cs.sk_company,
    cs.id_hubspot,
    ce.uuid_company,
    COALESCE(c.name, ce.company_name, cs.extracted_3p_tag, 'Unknown') AS company_name,
    COALESCE(c.tag_real_estate_agency, cs.extracted_3p_tag, 'Unknown') AS tag,
    COALESCE(c.extracted_3p_tag, cs.extracted_3p_tag, ce.trade_name, 'Unknown') AS extracted_3p_tag,
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
    COALESCE(c.sale_member_category, 'Unknown') AS sale_member_category,
    COALESCE(c.rent_member_category, 'Unknown') AS rent_member_category,
    COALESCE(c.company_cluster, 'Unknown') AS company_cluster,
    COALESCE(c.member_type, 'Unknown') AS member_type,
    COALESCE(c.address, ce.public_area, 'Unknown') AS address,
    COALESCE(c.zip_code, ce.zip_code, 'Unknown') AS zip_code,
    COALESCE(TRIM(UPPER(c.city)), ce.city, 'Unknown') AS city,
    COALESCE(c.state, ce.state_abbreviation, 'Unknown') AS state_abbreviation,
    COALESCE(s.name, c.state, ce.state, 'Unknown') AS state,
    COALESCE(c.country, IF(ce.country = 'Brasil', 'Brazil', ce.country), 'Unknown') AS country,
    COALESCE(c.country_code, 'Undefined') AS country_code,
    COALESCE(c.domain, 'Unknown') AS domain,
    COALESCE(c.e_mail, 'Unknown') AS e_mail,
    COALESCE(c.phone, 'Unknown') AS phone,
    COALESCE(c.industry, 'Unknown') AS industry,
    COALESCE(c.life_cycle_stage, 'Unknown') AS life_cycle_stage,
    COALESCE(c.mkt_campain, 'Unknown') AS mkt_campaign,
    COALESCE(c.mkt_channel, 'Unknown') AS mkt_channel,
    COALESCE(c.mkt_content, 'Unknown') AS mkt_content,
    COALESCE(c.mkt_medium, 'Unknown') AS mkt_medium,
    COALESCE(c.mkt_origin, 'Unknown') AS mkt_origin,
    COALESCE(c.mkt_source, 'Unknown') AS mkt_source,
    COALESCE(c.unified_discard_reasons, 'Unknown') AS discard_reason,
    COALESCE(c.lead_origin, 'Unknown') AS lead_origin,
    COALESCE(c.partnership_type, 'Unknown') AS partnership_type,
    COALESCE(c.first_conversion_event_name, 'Unknown') AS first_conversion_event_name,
    COALESCE(c.crm, 'Unknown') AS crm,
    COALESCE(c.real_estate_agency_focus, 'Unknown') AS real_estate_agency_focus,
    COALESCE(c.document, ce.document, 'Unknown') AS document,
    COALESCE(c.cnpj, ce.cnpj, 'Unknown') AS cnpj,
    COALESCE(c.rfc, ce.rfc, 'Unknown') AS rfc,
    COALESCE(c.creci, 'Unknown') AS creci,
    CASE
        WHEN c.is_juridical_person THEN 'PJ'
        WHEN c.is_natural_person THEN 'PF'
        ELSE 'Unknown'
    END AS person_type,
    c.num_associated_deals,
    c.num_associated_contacts,
    c.monthly_average_new_rental_contracts,
    c.num_managers,
    c.num_managed_properties,
    c.num_monthly_leads,
    c.average_sale_property_ticket,
    c.average_rent_property_ticket,
    c.monthly_repayment_volume_in_real,
    c.monthly_sale_volume_in_real,
    c.num_real_estate_agents,
    c.num_properties_for_sale,
    c.num_properties_for_rent,
    (
        COALESCE(c.sale_lead_status, '') IN ('Parceiro', 'Membro', 'Em processo tombamento')
        OR COALESCE(c.rent_lead_status, '') IN ('Parceiro', 'Membro', 'Em processo tombamento')
    ) AS is_partner,
    COALESCE(c.sale_lead_status, '') IN ('Parceiro', 'Membro', 'Em processo tombamento') AS is_sale_partner,
    COALESCE(c.rent_lead_status, '') IN ('Parceiro', 'Membro', 'Em processo tombamento') AS is_rent_partner,
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
    c.has_property_advertisement_online,
    c.is_correspondent_bank,
    c.is_lost,
    c.has_financing,
    COALESCE(c.is_for_sale, FALSE) OR COALESCE(ce.sale_listings_currently_owned, 0) > 0 AS is_for_sale,
    COALESCE(c.is_for_rent, FALSE) OR COALESCE(ce.rent_listings_currently_owned, 0) > 0 AS is_for_rent,
    c.has_partnerships_with_other_agencies,
    COALESCE(c.is_archived, FALSE) AS is_archived,
    c.ts_first_conversion,
    c.ts_recent_deal_close,
    c.ts_hubspot_owner_assigned,
    c.ts_last_logged_call,
    c.ts_notes_last_updated,
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
