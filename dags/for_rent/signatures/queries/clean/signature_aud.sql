SELECT
    id AS id_signature,
    recipient_id AS id_recipient,
    agreement_document_id AS id_agreement_document,
    signature_collector_id AS id_signature_collector,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    version,
    status,
    recipient_id_mod AS mod_id_recipient,
    agreement_document_id_mod AS mod_id_agreement_document,
    signature_collector_id_mod AS mod_id_signature_collector,
    status_mod AS mod_status,
    sent_at_mod AS mod_ts_sent,
    signed_at_mod AS mod_ts_signed,
    sent_at AS ts_sent,
    signed_at AS ts_signed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year(updated_at) AS year,
    month(updated_at) AS month,
    day(updated_at) AS day
FROM
    datalake_signatures_raw.signature_aud
WHERE
    date(updated_at) = date('{year}-{month}-{day}')