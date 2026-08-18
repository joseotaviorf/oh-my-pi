WITH ranked_repair_exempted AS (
    SELECT
        re.id_repair_request AS sk_repair_request,
        re.id_granted_by AS sk_exemption_granted_by,
        re.exemption_granted_by,
        re.responsibility,
        re.is_exempted,
        re.is_improper_repair,
        re.ts_granted,
        re.year,
        re.month,
        re.day,
        ROW_NUMBER() OVER (PARTITION BY re.id_repair_request ORDER BY re.ts_granted DESC) AS rn
    FROM
        datalake_inspections.repair_exempted AS re
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT DISTINCT
    sk_repair_request,
    sk_exemption_granted_by,
    exemption_granted_by,
    responsibility,
    is_exempted,
    is_improper_repair,
    ts_granted,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    ranked_repair_exempted
WHERE
    rn = 1
