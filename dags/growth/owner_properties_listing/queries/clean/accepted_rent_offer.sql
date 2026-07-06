SELECT
    id,
    property_id AS id_property,
    proposal_external_id AS id_proposal_external,
    processed_events,
    proposal_status,
    contract_document_status,
    demand_document_status,
    supply_document_status,
    demand_contract_document_status,
    supply_contract_document_status,
    contract_deadline AS ts_contract_deadline,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_accepted_rent_offer
