SELECT
    sss.id_response AS sk_answer,
    MD5(sss.email) AS sk_analyst,
    sss.id_survey AS sk_survey,
    sss.facility_satisfaction,
    sss.time_satisfaction,
    sss.support_satisfaction,
    sss.improvements_suggestions,
    sss.ts_submitted,
    CASE 
        WHEN day(ts_submitted) <= 7 THEN 'Week 1'
        WHEN day(ts_submitted) <= 14 THEN 'Week 2'
        WHEN day(ts_submitted) <= 21 THEN 'Week 3'
        WHEN day(ts_submitted) <= 28 THEN 'Week 4'
        ELSE 'Week 5'
       END AS week_month,
    NOW() AS ts_load,
    sss.year,
    sss.month,
    sss.day
FROM
    datalake_survicate.single_station_surveys AS sss
WHERE
    MAKE_DATE(sss.year, sss.month, sss.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
