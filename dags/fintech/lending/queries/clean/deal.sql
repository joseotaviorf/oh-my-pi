SELECT
    id,
    uuid,
    person_uuid AS uuid_person,
    value,
    product_id AS id_product,
    external_id AS id_external,
    created_at AS ts_created,
    updated_at AS ts_updated,
    offer_cohort_id AS id_offer_cohort
FROM 
    datalake_lending_raw.deal