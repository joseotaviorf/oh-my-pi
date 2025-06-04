SELECT
    id_operator AS sk_operator,
    id_agency,
    user_name,
    user_email,
    user_type,
    user_department,
    agency_type,
    agency_name,
    company_name,
    source,
    ts_user_created,
    NOW() AS ts_load
FROM datalake_collections_quintoandar.operators
