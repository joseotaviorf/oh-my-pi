SELECT
    id,
    visit_id AS id_visit,
    business_model,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.visit_business_model