SELECT
    CAST(round AS INTEGER) AS round,
    TO_DATE(start_date, "dd/MM/YY") AS ts_start,
    TO_DATE(end_date, "dd/MM/YY") AS ts_end
FROM
    datalake_gsheets_raw.agent_tiers_rounds
