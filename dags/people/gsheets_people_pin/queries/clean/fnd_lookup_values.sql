SELECT
    lookup_code,
    lookup_type,
    language,
    meaning,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.fnd_lookup_values
