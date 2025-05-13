SELECT
    id,
    external_id AS id_external,
    main_user_id AS id_main_user,
    request_status,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.boleto_user
