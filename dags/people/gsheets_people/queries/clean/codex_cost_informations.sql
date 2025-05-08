SELECT DISTINCT
    `CC Code` AS id_cost_center,
    `P&L Line Type` AS headcount_group,
    ts_load
WHERE
    `P&L Line Type` IS NOT NULL
FROM datalake_gsheets_people_raw.codex_cost_informations