SELECT
    sk_user AS id_user,
    team,
    range_start,
    range_end,
    obs,
    dt_start,
    dt_end
FROM
    datalake_gsheets_raw.asp_consultants_allocation
