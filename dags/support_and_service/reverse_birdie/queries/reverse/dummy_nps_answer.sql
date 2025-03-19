with main AS (
    SELECT 
        uuid() AS sk_nps_answer,
        CAST(rand() * 1000 AS INT) AS sk_user,
        uuid() AS uuid_person,
        CONCAT('Campaign_', CAST(rand() * 100 AS INT)) AS campaign_name,
        CONCAT('Comment_', CAST(rand() * 1000 AS INT)) AS comment,
        CASE WHEN rand() < 0.5 THEN 'Positive' ELSE 'Negative' END AS score_category,
        year(date_format(current_date() - CAST(rand() * 90 AS INT), 'yyyy-MM-dd')) AS year,
        month(date_format(current_date() - CAST(rand() * 90 AS INT), 'yyyy-MM-dd')) AS month,
        day(date_format(current_date() - CAST(rand() * 90 AS INT), 'yyyy-MM-dd')) AS day,
        CURRENT_DATE AS ts_load
    FROM
        range(1000)
    )
SELECT 
    *, 
    MAKE_DATE(year, month, day) AS ts_answer
FROM
    main 