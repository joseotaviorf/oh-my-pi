SELECT
    salary_basis_id AS id_salary_basis,
    language,
    source_lang AS source_language,
    salary_basis_name,
    display_name,
    created_by,
    last_updated_by AS updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_compensation_raw.cmp_salary_bases_tl
