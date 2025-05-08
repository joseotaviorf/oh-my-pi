SELECT
    id_convenia,
    email AS work_email,
    registration AS legacy_registration,
    ts_load
FROM datalake_gsheets_people_raw.legacy_registration
