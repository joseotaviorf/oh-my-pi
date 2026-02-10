SELECT
    id,
    profile_id AS id_profile,
    person_uuid AS uuid_person,
    company_product_product_id AS id_product,
    company_product_company_id AS id_company,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.member_profile