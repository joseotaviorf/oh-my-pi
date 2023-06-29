SELECT
    account_name,
    hashed_email,
    population,
    CAST(dt_import AS DATE) AS dt_import
FROM
    datalake_gsheets_raw.rent_criteo_eng_ab_test
