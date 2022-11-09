SELECT
    id,
    code,
    name,
    default_locale,
    default_timezone,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.country