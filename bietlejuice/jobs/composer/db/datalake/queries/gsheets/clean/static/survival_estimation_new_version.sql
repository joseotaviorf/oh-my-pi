SELECT
    CAST(first_rentals AS INTEGER) AS first_rentals,
    CAST(months_after_first_contract AS INTEGER) AS months_after_first_contract,
    CAST(total_re_rentals AS INTEGER) AS total_re_rentals,
    CAST(total_rentals AS INTEGER) AS total_rentals,
    CAST(ended_first_rentals AS INTEGER) AS ended_first_rentals,
    CAST(ended_re_rentals AS INTEGER) AS ended_re_rentals,
    CAST(ended_rentals AS INTEGER) AS ended_rentals,
    CAST(year AS INTEGER) AS year,
    TO_DATE(contract_start_month, 'yyyy-MM-dd') AS dt_contract_started_month,
    TO_DATE(months_after, 'yyyy-MM-dd') AS dt_month_after,
    TO_DATE(dt_last_updated, 'yyyy-MM-dd') AS dt_last_updated
FROM
    datalake_gsheets_raw.survival_estimation_new_version
