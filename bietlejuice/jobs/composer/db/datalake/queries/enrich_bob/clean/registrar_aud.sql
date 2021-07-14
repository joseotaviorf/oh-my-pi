SELECT
    id AS id_registrar,
    main_id AS id_main,
    rev,
    revtype AS rev_type,
    main_id_mod AS mod_id_main,
    house_drafts_mod AS mod_house_drafts
FROM datalake_bob_raw.registrar_aud