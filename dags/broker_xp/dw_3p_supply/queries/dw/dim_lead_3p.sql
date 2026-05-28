SELECT
  l.id_lead_3p AS sk_lead_3p,
  COALESCE(l.id_house, -1) AS sk_house,
  l.cnpj,
  l.address,
  l.number,
  l.floor,
  l.complement,
  l.neighborhood,
  l.city,
  l.state_acronym,
  l.country,
  l.country_code,
  l.zip_code,
  l.rent AS rent_price,
  l.sale_price,
  l.condo_price,
  l.total_area,
  l.bedrooms,
  l.suites,
  l.bathrooms,
  l.garages,
  l.house_type,
  l.house_description,
  l.owner_person_type,
  l.owner_agent_relationship,
  l.access_type,
  l.authorization_type,
  l.occupant_type,
  l.condominium,
  l.construction_year,
  l.block,
  l.tower,
  COALESCE(sale_blr.recurrency_type, 'N/A') AS sale_recurrency_type,
  COALESCE(rent_blr.recurrency_type, 'N/A') AS rent_recurrency_type,
  l.is_out_of_area,
  l.is_iptu_not_paid,
  l.has_restriction,
  l.has_balcony,
  l.is_furnished,
  l.is_habitat,
  l.has_agency_key,
  l.has_concierge,
  l.has_3p_access_control,
  l.ts_lead_created,
  l.ts_lead_updated,
  l.ts_sale_business_context_created,
  l.ts_rent_business_context_created,
  l.ts_lead_created_broker_crm,
  l.ts_lead_updated_broker_crm,
  CURRENT_TIMESTAMP() AS ts_load,
  l.year,
  l.month,
  l.day
FROM
  datalake_3p_supply.lead_3p AS l
LEFT JOIN
  datalake_3p_supply.broker_lead_relationship AS sale_blr
    ON sale_blr.id_lead_3p = l.id_lead_3p
    AND sale_blr.business_context = 'SALE'
LEFT JOIN
  datalake_3p_supply.broker_lead_relationship AS rent_blr
    ON rent_blr.id_lead_3p = l.id_lead_3p
    AND rent_blr.business_context = 'RENT'
