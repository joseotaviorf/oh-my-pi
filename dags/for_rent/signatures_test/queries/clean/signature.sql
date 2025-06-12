SELECT
    id,
    recipient_id AS id_recipient,
    agreement_document_id AS id_agreement_document,
    signature_collector_id AS id_signature_collector,
    version,
    status,
    sent_at AS ts_sent,
    signed_at AS ts_signed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_signatures_test_raw.signature
