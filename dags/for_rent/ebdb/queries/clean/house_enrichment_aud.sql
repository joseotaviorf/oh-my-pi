SELECT
    id,
    house_id AS id_house,
    dejavu_id AS id_dejavu,
    status,
    event_trigger,
    dejavu_id_version AS version_id_dejavu,
    rev,
    REVTYPE AS rev_type,
    house_id_MOD AS mod_id_house,
    dejavu_id_MOD AS mod_id_dejavu,
    status_MOD AS mod_status,
    event_trigger_MOD AS mod_event_trigger,
    dejavu_id_version_MOD AS mod_version_id_dejavu,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.houseenrichment_aud