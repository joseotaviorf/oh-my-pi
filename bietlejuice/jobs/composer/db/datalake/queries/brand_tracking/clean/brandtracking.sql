SELECT
    respondent_serial AS id_respondent,
    market,
    regiao AS region,
    wave,
    qmktsize_2_1 AS city,
    qmktsize_6_1 AS state,
    gender,
    age,
    renda AS income,
    cs AS civil_status,
    flagt1 AS target,
    year,
    quarter
FROM
    datalake_brand_tracking_raw.brandtracking
WHERE
    year = {year_previous_quarter}
    AND quarter = {previous_quarter}