SELECT 
    uuid() AS sk_nps_answer,
    uuid() AS uuid_person,
    CONCAT('Campaign_', CAST(rand() * 100 AS INT)) AS campaign_name,
    CONCAT('Comment_', CAST(rand() * 1000 AS INT)) AS comment,
    CASE WHEN rand() < 0.5 THEN 'Positive' ELSE 'Negative' END AS score_category,
    date_format(current_date() - CAST(rand() * 365 AS INT), 'yyyy-MM-dd') AS ts_answer,
    CAST(rand() * 1000 AS INT) AS sk_user
FROM
    range(1000)