SELECT
    id AS id_company,
    properties,
    properties_with_history,
    associations,
    archived AS is_archived,
    TRUE AS has_3p_access_control,
    archived_at AS ts_archived,
    created_at AS ts_created,
    updated_at AS ts_updated,
    ts_load,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) AS day
FROM
    datalake_hubspot_test_raw.company
