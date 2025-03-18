SELECT 
    id_user,
    id_partner,
    status_ciq,
    ciq_type,
    city_group_partner,
    n_fl,
    n_fl_valid,
    rev_share,
    DATE(dt_start_audit) AS dt_start_audit,
    DATE(dt_end_audit) AS dt_end_audit,
    DATE(dt_start_validity) AS dt_start_validity,
    DATE(dt_end_validity) AS dt_end_validity,
    TIMESTAMP(ts_updated) AS ts_updated
FROM 
    datalake_gsheets_raw.ciq_tiers_rent