SELECT
    id,
    account_manager_id AS id_account_manager,
    pp_multi_uuid,
    person_uuid,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.pp_multi_user
