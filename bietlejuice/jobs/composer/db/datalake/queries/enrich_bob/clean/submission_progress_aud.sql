SELECT
    house_draft_id AS id_house_draft,
    external_id AS id_external,
    rev,
    revtype AS rev_type,
    attempts,
    status,
    error_description,
    house_draft_mod AS mod_id_house_draft,
    external_id_mod AS mod_id_external,
    attempts_mod AS mod_attempts,
    status_mod AS mod_status,
    error_description_mod AS mod_error_description
FROM datalake_bob_raw.submission_progress_aud