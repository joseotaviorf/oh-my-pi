SELECT
    id as id_recipient,
    internal_reference_id AS id_internal_reference,
    external_reference_id AS id_external_reference,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    internal_reference_name,
    external_reference_name,
    version,
    name,
    email,
    dtype as type,
    internal_reference_mod AS mod_id_internal_reference,
    external_reference_mod AS mod_id_external_reference,
    name_mod AS mod_name,
    email_mod AS mod_email,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_signatures_incremental_raw.recipient_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}