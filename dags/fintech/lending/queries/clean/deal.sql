SELECT
    id,
    offer_cohort_id AS id_offer_cohort,
    offer_term_id AS id_offer_term,
    product_id AS id_product,
    external_id AS id_external,
    uuid,
    person_uuid AS uuid_person,
    value,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_lending_raw.deal
