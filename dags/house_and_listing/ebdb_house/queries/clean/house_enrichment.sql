SELECT
    id,
    house_id AS id_house,
    dejavu_id AS id_dejavu,
    status,
    event_trigger,
    granularity,
    dejavu_id_version AS version_id_dejavu,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.houseenrichment