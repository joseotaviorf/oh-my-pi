SELECT
    id,
    house_id AS id_house,
    status,
    event_trigger,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.houseenrichment