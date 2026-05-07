SELECT
    id,
    business_association,
    name,
    description,
    s3_key,
    reason,
    author_type,
    author_identifier,
    valid_from AS dt_valid_from,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.AccreditationContractTemplate 