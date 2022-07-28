SELECT
    id,
    main_id AS id_main,
    name,
    email,
    telephone,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.simulation_user