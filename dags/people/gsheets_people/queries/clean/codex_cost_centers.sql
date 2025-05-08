SELECT
    `CC Legacy` AS id_cost_center_legacy,
    `CC Code` AS id_cost_center_current,
    CAST(`Sort` AS INT) AS id_sort
    CAST(`Team Code` AS INT) AS id_team,
    `CC Full Name` AS cost_center_full_name,
    `CC Name` AS cost_center_name_no_code,
    Business AS business,
    Product AS product,
    Brand AS brand,
    `Team Name` AS team,
    `Structure Name` AS structure,
    `P&T Chapter` AS chaper,
    `P&T Line` AS line,
    `F&P Owner` AS owner_fep_email,
    L1 AS owner_l1_email,
    L2 AS owner_l2_email,
    L3 AS owner_l3_email,
    `Status` AS cost_center_status,
    ts_load
FROM datalake_gsheets_people_raw.codex_cost_centers