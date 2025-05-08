SELECT
    fechamento AS closure,
    quarter,
    target_rl_grupo AS target_rl_group,
    target_rl_adquiridas AS target_rl_acquired,
    target_3_mo_to,
    target_turnover,
    pwd_target,
    target_enps,
    voluntary_rt_grupo AS voluntary_rt_group,
    voluntary_rt_navent,
    actual_enps AS current_enps,
    ts_load
FROM datalake_gsheets_people_raw.targets_turnover