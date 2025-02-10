SELECT
    id,
    house_owner_id AS id_house_owner,
    acquisition_id AS id_acquisition,
    address_id AS id_address,
    referred_by AS id_referred_by,
    external_reference_id AS id_external_reference,
    new_id AS id_lead_ebdb,
    external_reference_name,
    reason,
    status,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    year,
    month,
    day
FROM
    datalake_rene_descartes_raw.house_lead_aud
