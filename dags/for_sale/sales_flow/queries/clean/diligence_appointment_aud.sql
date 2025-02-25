SELECT
    id AS id_diligence_appointment_aud,
    diligence_id AS id_diligence,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    appointment,
    diligence_id_mod AS mod_id_diligence,
    appointment_mod AS mod_appointment,
    deleted_at_mod AS mod_ts_deleted,
    deleted_at AS ts_deleted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.diligence_appointment_aud
