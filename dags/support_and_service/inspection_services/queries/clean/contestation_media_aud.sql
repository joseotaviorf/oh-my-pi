SELECT
    id AS id_contestation_media,
    contestation_id AS id_contestation,
    uuid,
    type,
    name,
    rev,
    revtype,
    revend,
    contestation_id_mod AS mod_id_contestation,
    uuid_mod AS mod_uuid,
    type_mod AS mod_type,
    name_mod AS mod_name,
    contestation_mod AS mod_contestation,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_updated,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.contestation_media_aud
