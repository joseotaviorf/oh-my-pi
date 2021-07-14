SELECT
    house_draft_id AS id_house_draft,
    external_id AS id_external,
    attempts,
    status,
    error_description
FROM datalake_bob_raw.submission_progress