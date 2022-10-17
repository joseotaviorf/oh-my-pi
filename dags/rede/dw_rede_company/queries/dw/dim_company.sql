SELECT
    cs.sk_company,
    cs.id_hubspot,
    COALESCE(c.name, 'Unknown') AS company_name,
    COALESCE(c.tag_real_estate_agency, 'Unknown') AS tag,
    COALESCE(c.extracted_3p_tag, 'Unknown') AS extracted_3p_tag,
    COALESCE(c.lead_status, 'Unknown') AS lead_status,
    CASE
        WHEN t.team_name IN ('BH Sul', 'BH Norte') THEN '3P BH'
        ELSE '3P 5A' 
    END AS product,
    COALESCE(c.address, 'Unknown') AS address,
    COALESCE(c.zip_code, 'Unknown') AS zip_code,
    COALESCE(TRIM(UPPER(c.city)), 'Unknown') AS city,
    COALESCE(c.state, 'Unknown') AS state,
    COALESCE(c.country, 'Unknown') AS country,
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
    COALESCE(c.cnpj, 'Unknown') AS cnpj,
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
    c.lead_status IN ('Parceiro', 'Membro', 'Em processo tombamento') AS is_partner,
    t.team_name IN ('BH Sul', 'BH Norte') AS is_3p_bh,
    t.team_name NOT IN ('BH Sul', 'BH Norte') AS is_3p_5a,
    c.has_property_advertisement_online,
    c.is_correspondent_bank,
    c.is_lost,
    c.has_financing,
    c.is_for_sale,
    c.is_for_rent,
    c.has_partnerships_with_other_agencies,
    c.ts_first_conversion,
    c.ts_recent_deal_close,
    c.ts_hubspot_owner_assigned,
    c.ts_last_logged_call,
    c.ts_notes_last_updated,
    c.ts_created,
    c.ts_updated,
    NOW() AS ts_load
FROM
    datalake_hubspot.company AS c
JOIN
    datalake_rede_company.company_sks AS cs
        ON c.id_company = cs.id_hubspot
JOIN
    datalake_hubspot.deal AS d
        ON d.id_company = c.id_company
JOIN
    datalake_hubspot.team AS t 
        ON t.id_team = d.id_hubspot_team
WHERE
    d.id_pipeline = 5160960 -- We only want companies in the negotiation pipeline for Rede QuintoAndar.
    AND d.id_hubspot_team NOT IN (6194580,5795941) -- With a deal not made by adm or help sales
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY c.id_company ORDER BY d.ts_created DESC) = 1 -- There may be more than one deal. We want the most recent one.