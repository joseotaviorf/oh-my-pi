SELECT
    id,
    pp_multi_user_id AS id_pp_multi_user,
    triggered_by_id AS id_triggered_by,
    pp_multi_fee_id AS id_pp_multi_fee,
    execution_type,
    event_log_type,
    description,
    previous_status,
    new_status,
    previous_adm_fee,
    new_adm_fee,
    previous_fee_active AS is_previous_fee_active,
    new_fee_active AS is_new_fee_active,
    created_at AS ts_created
FROM
    datalake_rental_management_raw.pp_multi_audit_log
