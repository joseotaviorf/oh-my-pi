WITH date_range AS (
    SELECT
        EXPLODE(SEQUENCE(TO_DATE('2010-01-01'), TO_DATE('2050-01-01'), INTERVAL 1 day)) AS date
),
ongoing_real_estate_agency AS (
    SELECT *
    FROM
        datalake_casa_mineira_portal.real_estate_status AS rea_status
    JOIN 
        date_range
            ON (date_range.date 
                    BETWEEN CAST(rea_status.ts_created AS DATE)
                    AND COALESCE(CAST(rea_status.ts_status_ended AS DATE), CURRENT_DATE) 
                )
    WHERE 
        status = 'CREATED'
        OR status = 'REACTIVATED'
)
SELECT
    CAST(DATE_FORMAT(date, 'yyyyMMdd') AS INT) AS sk_count_evaluated_date,
    COUNT(id_real_estate_agency) AS ongoing_real_estate_agency,
    date AS dt_count_evaluated,
    NOW() AS ts_load
FROM
    ongoing_real_estate_agency
GROUP BY 
    sk_count_evaluated_date,
    dt_count_evaluated
