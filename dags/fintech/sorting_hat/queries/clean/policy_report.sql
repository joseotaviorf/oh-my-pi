SELECT
    id,
    external_id AS id_external,
    type,
    external_source,
    result,
    raw_data,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_sorting_hat_raw.policyreport