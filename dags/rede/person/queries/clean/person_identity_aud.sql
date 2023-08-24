SELECT
    id,
    person_id AS id_person,
    value,
    scope,
    type,
    validation_type,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    person_id_mod AS mod_id_person,
    value_mod AS mod_value,
    scope_mod AS mod_scope,
    type_mod AS mod_type,
    validation_type_mod AS mod_validation_type,
    last_validated_at_mod AS mod_ts_last_validated,
    last_validated_at AS ts_last_validated,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_person_raw.person_identity_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}