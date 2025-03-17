SELECT
    lookup_code,
    lookup_type,
    language AS language_code,
    meaning,
    NOW() AS ts_load
FROM
    datalake_gsheets_hcm_db_raw.fnd_lookup_values
