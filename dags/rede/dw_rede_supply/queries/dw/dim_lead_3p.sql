WITH houses AS (
    SELECT
        id,
        house_type LIKE '%CASA%'
        OR house_type LIKE '%SOBRADO%' 
        OR house_type LIKE '%HOUSE%' AS is_house
    FROM
        datalake_brokers_supply_processor.lead_3p
),
listing_relation AS (
    SELECT
        lr.id_house,
        lr.id_related
    FROM
        datalake_ebdb_clean.house_listing_relation AS lr
    WHERE
        lr.related_as = 'OWNER_AGENT'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY lr.id_house ORDER BY lr.id_listing_business_context) = 1
)
SELECT
    lsk.sk_lead_3p,
    l.id AS id_lead_3p,
    l.id_lead_first_version_global,
    l.id_lead_first_version_by_company,
    l.id_house,
    COALESCE(l.id_by_real_estate, l.id_house_partner) AS id_by_real_estate,
    l.lead_hash,
    lr.id_related AS uuid_person_owner_agent,
    COALESCE(lsc_sale.status, 'N/A') AS sale_status,
    COALESCE(lsc_rent.status, 'N/A') AS rent_status,
    COALESCE(lsc_sale.growth_status, 'N/A') AS sale_growth_status,
    COALESCE(lsc_rent.growth_status, 'N/A') AS rent_growth_status,
    COALESCE(c.name, 'Unknown') AS company_name,
    COALESCE(c.tag_real_estate_agency, 'Unknown') AS company_tag,
    COALESCE(C.extracted_3p_tag, 'Unknown') AS extracted_3p_tag,
    COALESCE(l.sale_integrator_trade_name, 'N/A') AS sale_integrator_trade_name,
    COALESCE(l.rent_integrator_trade_name, 'N/A') AS rent_integrator_trade_name,
    COALESCE(l.sale_recurrency_type, 'N/A') AS sale_recurrency_type,
    COALESCE(l.rent_recurrency_type, 'N/A') AS rent_recurrency_type,
    COALESCE(la_sale.acquisition_team, 'N/A') AS sale_acquisition_team,
    COALESCE(la_rent.acquisition_team, 'N/A') AS rent_acquisition_team,
    COALESCE(lf_sale.freshness, 'N/A') AS sale_freshness,
    COALESCE(lf_rent.freshness, 'N/A') AS rent_freshness,
    COALESCE(l.house_category, 'Unknown') AS house_category,
    COALESCE(l.house_type, 'Unknown') AS house_type, 
    COALESCE(l.house_subtype, 'Unknown') AS house_subtype, 
    COALESCE(l.front_door_type, 'Unknown') AS front_door_type, 
    COALESCE(l.house_description, 'Unknown') AS house_description, 
    COALESCE(l.country, 'Unknown') AS country, 
    COALESCE(l.state, 'Unknown') AS state, 
    COALESCE(l.city, 'Unknown') AS city, 
    COALESCE(l.neighborhood, 'Unknown') AS neighborhood, 
    COALESCE(l.region_slug, 'Unknown') AS region_slug, 
    COALESCE(l.zip_code, 'Unknown') AS zip_code, 
    COALESCE(l.address, 'Unknown') AS address,
    COALESCE(l.number, 'Unknown') AS number,
    COALESCE(l.block, CASE WHEN h.is_house THEN 'N/A' ELSE 'Unknown' END) AS block,
    COALESCE(l.tower, CASE WHEN h.is_house THEN 'N/A' ELSE 'Unknown' END) AS tower,
    COALESCE(l.floor, CASE WHEN h.is_house THEN 'N/A' ELSE 'Unknown' END) AS floor,
    COALESCE(l.complement, CASE WHEN h.is_house THEN 'N/A' ELSE 'Unknown' END) AS complement,
    COALESCE(l.reference_point, 'Unknown') AS reference_point,
    COALESCE(l.condominium, 'Unknown') AS condominium,
    COALESCE(l.owner_person_type, 'Unknown') AS owner_person_type,
    COALESCE(l.access_type, 'Unknown') AS access_type,
    COALESCE(l.authorization_type, 'Unknown') AS authorization_type,
    COALESCE(l.occupant_type, 'Unknown') AS occupant_type,
    COALESCE(l.additional_access_info, 'Unknown') AS additional_access_info,
    COALESCE(l.locker_address, 'Unknown') AS locker_address,
    COALESCE(l.password, 'Unknown') AS password,
    COALESCE(l.cnpj, 'Unknown') AS cnpj,
    l.version_global,
    l.sale_version_global,
    l.rent_version_global,
    l.version_by_company,
    l.sale_version_by_company,
    l.rent_version_by_company,
    l.iptu_installment_informations[0]['installmentAmount'] AS iptu_installment_amount,
    l.iptu_installment_informations[0]['installmentQuantity'] AS iptu_installment_quantity,
    l.latitude,
    l.longitude,
    l.rent_price,
    l.sale_price,
    l.total_area, 
    l.bedrooms, 
    l.suites, 
    l.bathrooms, 
    l.garages,
    l.is_for_sale,
    l.is_for_rent,
    l.has_opted_keys_with_agent,
    l.has_access_restriction,
    l.is_furnished,
    l.is_penthouse,
    l.is_pet_friendly,
    l.is_iptu_not_paid,
    l.is_out_of_area,
    l.is_habitat,
    l.has_balcony,
    l.has_agency_key,
    l.has_concierge,
    lf_sale.is_fresh AS is_fresh_in_sale,
    lf_sale.is_early_fresh AS is_early_fresh_in_sale,
    lf_rent.is_fresh AS is_fresh_in_rent,
    lf_rent.is_early_fresh AS is_early_fresh_in_rent,
    GREATEST(lsc_sale.is_waiting_for_enrichment, lsc_rent.is_waiting_for_enrichment) AS is_waiting_for_enrichment,
    COALESCE(lsc_sale.is_waiting_for_enrichment, FALSE) AS is_waiting_for_enrichment_in_sale,
    COALESCE(lsc_rent.is_waiting_for_enrichment, FALSE) AS is_waiting_for_enrichment_in_rent,
    GREATEST(lsc_sale.is_ineligible, lsc_rent.is_ineligible) AS is_ineligible,
    COALESCE(lsc_sale.is_ineligible, FALSE) AS is_ineligible_in_sale,
    COALESCE(lsc_rent.is_ineligible, FALSE) AS is_ineligible_in_rent,
    GREATEST(lsc_sale.is_discarded, lsc_rent.is_discarded) AS is_discarded,
    COALESCE(lsc_sale.is_discarded, FALSE) AS is_discarded_in_sale,
    COALESCE(lsc_rent.is_discarded, FALSE) AS is_discarded_in_rent,
    l.is_sent_to_main,
    l.is_first_version_global,
    l.is_first_sale_version_global,
    l.is_first_rent_version_global,
    l.is_first_version_by_company,
    l.is_first_sale_version_by_company,
    l.is_first_rent_version_by_company,
    l.is_last_version_global,
    l.is_last_sale_version_global,
    l.is_last_rent_version_global,
    l.is_last_version_by_company,
    l.is_last_sale_version_by_company,
    l.is_last_rent_version_by_company,
    lf_sale.dt_crawler AS dt_crawler_in_sale,
    lf_rent.dt_crawler AS dt_crawler_in_rent,
    l.ts_first_version_created_global,
    l.ts_first_sale_version_created_global,
    l.ts_first_rent_version_created_global,
    l.ts_first_version_created_by_company,
    l.ts_first_sale_version_created_by_company,
    l.ts_first_rent_version_created_by_company,
    l.ts_house_created,
    l.ts_house_updated,
    l.ts_created,
    l.ts_updated,
    NOW() AS ts_load
FROM
    datalake_brokers_supply_processor.lead_3p AS l
JOIN
    houses AS h
        ON l.id = h.id
JOIN
    datalake_rede_supply.lead_3p_sks AS lsk
        ON l.id = lsk.id_lead_3p
LEFT JOIN
    datalake_rede_supply.lead_3p_status_changes AS lsc_sale
        ON lsc_sale.id_lead_3p = l.id
        AND lsc_sale.business_context = 'SALE'
        AND lsc_sale.ts_status_ended IS NULL
LEFT JOIN
    datalake_rede_supply.lead_3p_status_changes AS lsc_rent
        ON lsc_rent.id_lead_3p = l.id
        AND lsc_rent.business_context = 'RENT'
        AND lsc_rent.ts_status_ended IS NULL
LEFT JOIN
    datalake_hubspot.company AS c
        ON c.id_company = COALESCE(l.id_company_hubspot, lsc_sale.id_company_hubspot, lsc_rent.id_company_hubspot)
LEFT JOIN
    datalake_rede_lead_acquisition.lead_3p_acquisition AS la_sale
        ON la_sale.id_lead_3p = l.id
        AND la_sale.business_context = 'SALE'
LEFT JOIN
    datalake_rede_lead_acquisition.lead_3p_acquisition AS la_rent
        ON la_rent.id_lead_3p = l.id
        AND la_rent.business_context = 'RENT'
LEFT JOIN
    datalake_rede_lead_crawler.lead_3p_freshness AS lf_sale
        ON lf_sale.id_lead_3p = l.id
        AND lf_sale.business_context = 'SALE'
LEFT JOIN
    datalake_rede_lead_crawler.lead_3p_freshness AS lf_rent
        ON lf_rent.id_lead_3p = l.id
        AND lf_rent.business_context = 'RENT'
LEFT JOIN
    listing_relation AS lr
        ON l.id_house = lr.id_house