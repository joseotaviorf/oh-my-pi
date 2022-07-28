SELECT
    id,
    external_reference_id AS id_external_reference,
    rejection_history_collector_id AS id_rejection_history_collector,
    external_reference_name,
    reason,
    business_context,
    created_at AS ts_created,
    updated_at AS ts_updated,
    rejected_at AS ts_rejected
FROM
    datalake_rene_descartes_raw.rejection_history_event