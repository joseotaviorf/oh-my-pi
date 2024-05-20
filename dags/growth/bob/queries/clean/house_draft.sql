SELECT
    id,
    client_side_id AS id_client_side,
    original_lead_id AS id_original_lead,
    registrar,
    owners,
    details,
    access,
    pricing,
    blueprint,
    status,
    business_context,
    type,
    administrators,
    attendance_info,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_bob_raw.house_draft
