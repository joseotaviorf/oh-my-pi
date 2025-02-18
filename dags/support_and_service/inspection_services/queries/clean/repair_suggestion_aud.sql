SELECT
    id,
    service,
    type,
    responsibility,
    exempted AS is_exempted,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    service_mod AS mod_service,
    type_mod AS mod_type,
    responsibility_mod AS mod_responsibility,
    exempted_mod AS mod_is_exempted,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.repair_suggestion_aud
