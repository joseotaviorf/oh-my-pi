SELECT
    respondent_serial AS id_respondent,
    id_question,
    wave,
    answer,
    year,
    quarter
FROM
    datalake_brand_tracking_raw.brandtracking_unpivoted
WHERE
    year = {year_previous_quarter}
    AND quarter = {previous_quarter}