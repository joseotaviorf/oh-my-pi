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
    year(updated_at) AS year,
    month(updated_at) AS month,
    day(updated_at) AS day
FROM
    datalake_signatures_raw.recipient_aud
WHERE
    date(updated_at) = date('{year}-{month}-{day}')