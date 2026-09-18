SELECT
    id,
    client_side_id AS id_client_side,
    original_lead_id AS id_original_lead,
    lead_intent_id AS id_lead_intent,
    registrar,
    owners,
    details,
    access,
    pricing,
    blueprint,
    status,
    business_context,
    social_housing_program,
    type,
    administrators,
    attendance_info,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_bob_raw.house_draft
