SELECT
    id,
    third_party_bills_id AS id_third_party_bills,
    event_type,
    channel,
    author_type,
    author_identifier,
    description,
    created_at AS ts_created
FROM
    datalake_rental_management_raw.third_party_bills_audit_log
