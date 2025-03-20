SELECT
    id,
    parent_id AS id_parent,
    company_uuid AS uuid_company,
    company_name,
    trade_name,
    company_type,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.company