SELECT
    house_draft_id AS id_house_draft,
    confirmation_attempts,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_bob_raw.attribution_progress