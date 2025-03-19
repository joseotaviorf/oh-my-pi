with main AS (
                SELECT 
                    uuid() AS sk_nps_answer,
                    CAST(rand() * 1000 AS INT) AS sk_user,
                    uuid() AS uuid_person,
                    CONCAT('Campaign_', CAST(rand() * 100 AS INT)) AS campaign_name,
                    CONCAT('Comment_', CAST(rand() * 1000 AS INT)) AS comment,
                    rand() AS score,
                    year(date_format(current_date() - CAST(rand() * 90 AS INT), 'yyyy-MM-dd')) AS year,
                    month(date_format(current_date() - CAST(rand() * 90 AS INT), 'yyyy-MM-dd')) AS month,
                    day(date_format(current_date() - CAST(rand() * 90 AS INT), 'yyyy-MM-dd')) AS day,
                    CURRENT_DATE AS ts_load
                FROM
                    range(1000)
                )
            SELECT 
                m.sk_nps_answer,
                m.sk_user,
                m.uuid_person,
                m.campaign_name,
                m.score,
                m.comment,
                CASE WHEN m.score < 0.5 THEN 'Positive' ELSE 'Negative' END AS score_category,
                m.year,
                m.month,
                m.day,
                MAKE_DATE(m.year, m.month, m.day) AS ts_answer,
                m.ts_load
            FROM
                main AS m