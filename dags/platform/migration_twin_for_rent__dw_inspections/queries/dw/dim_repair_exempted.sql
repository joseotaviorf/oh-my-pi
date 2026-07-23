SELECT DISTINCT
    re.id_repair_request AS sk_repair_request,
    re.id_granted_by AS sk_exemption_granted_by,
    re.exemption_granted_by,
    re.responsibility,
    re.is_exempted,
    re.is_improper_repair,
    re.ts_granted,
    NOW() AS ts_load,
    re.year,
    re.month,
    re.day
FROM
    datalake_inspections.repair_exempted AS re
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_repair_request ORDER BY ts_granted DESC) = 1
