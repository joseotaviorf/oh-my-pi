SELECT
    ic.id_answer AS sk_answer,
    COALESCE(ic.id_inspection, -1) AS sk_inspection,
    COALESCE(ic.id_contract, -1) AS sk_contract,
    NOW() AS ts_load,
    ic.year,
    ic.month,
    ic.day
FROM
    datalake_inspections_metrics.inspection_csat AS ic
WHERE
    ic.year = {year}
    AND ic.month = {month}
    AND ic.day = {day}