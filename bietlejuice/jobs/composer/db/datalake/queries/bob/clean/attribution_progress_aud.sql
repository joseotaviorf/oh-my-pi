SELECT
    house_draft_id AS id_house_draft,
    rev,
    revtype AS rev_type,
    confirmation_attempts,
    status,
    house_draft_mod AS mod_id_house_draft,
    confirmation_attempts_mod AS mod_confirmation_attempts,
    status_mod AS mod_status
FROM datalake_bob_raw.attribution_progress_aud