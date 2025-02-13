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
    created_at AS ts_created,
    updated_at AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) AS day
FROM
    datalake_rene_descartes_raw.house_lead
