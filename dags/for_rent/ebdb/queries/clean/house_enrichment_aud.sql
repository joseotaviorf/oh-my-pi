SELECT
    id,
    house_id AS id_house,
    status,
    event_trigger,
    rev,
    REVTYPE AS rev_type,
    house_id_MOD AS mod_id_house,
    status_MOD AS mod_status,
    event_trigger_MOD AS mod_event_trigger,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.houseenrichment_aud