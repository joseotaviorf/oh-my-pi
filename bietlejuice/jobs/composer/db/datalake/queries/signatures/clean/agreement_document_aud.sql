SELECT
    id AS id_agreement_document,
    internal_reference_id AS id_internal_reference,
    external_reference_id AS id_external_reference,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    internal_reference_name,
    external_reference_name,
    version,
    type,
    document_s3_uid,
    name,
    email_subject,
    email_body,
    signed_document_s3_uid,
    internal_reference_mod AS mod_id_internal_reference,
    external_reference_mod AS mod_id_external_reference,
    type_mod AS mod_type,
    document_s3_uid_mod AS mod_document_s3_uid,
    name_mod AS mod_name,
    email_subject_mod AS mod_email_subject,
    email_body_mod AS mod_email_body,
    signed_document_s3_uid_mod AS mod_signed_document_s3_uid,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year(updated_at) AS year,
    month(updated_at) AS month,
    day(updated_at) AS day
FROM
    datalake_signatures_raw.agreement_document_aud
WHERE
    date(updated_at) = date('{year}-{month}-{day}')