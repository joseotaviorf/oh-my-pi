SELECT
    id,
    vendor_natural_key,
    resource_code,
    payload,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
