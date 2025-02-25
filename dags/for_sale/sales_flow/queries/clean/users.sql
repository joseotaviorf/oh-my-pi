SELECT
    id,
    external_id AS id_external,
    name,
    email,
    phone,
    type,
    cpf,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.users
