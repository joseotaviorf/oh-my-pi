SELECT
    id,
    internal_reference_id AS id_internal_reference,
    external_reference_id AS id_external_reference,
    internal_reference_name,
    external_reference_name,
    version,
    type,
    document_s3_uid,
    name,
    email_subject,
    email_body,
    signed_document_s3_uid,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_signatures_test_raw.agreement_document
