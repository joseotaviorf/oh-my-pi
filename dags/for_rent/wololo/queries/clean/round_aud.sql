SELECT
    prospect_id AS id_prospect,
    reference_id AS id_reference,
    round_count AS round_number,
    max_tries AS round_max_tries,
    maxtries_mod AS mod_round_max_tries,
    rev,
    revtype AS rev_type,
    revend AS rev_end
FROM
    datalake_wololo_raw.round_aud