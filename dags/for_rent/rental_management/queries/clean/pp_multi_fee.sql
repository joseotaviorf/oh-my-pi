SELECT
    id,
    pp_multi_user_id AS id_pp_multi_user,
    version,
    CAST(adm_fee AS DECIMAL(38, 10)) AS adm_fee,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.pp_multi_fee
