SELECT
    id_creditor,
    id_customer,
    historical_code,
    situation_occurrence,
    operator_name,
    occurence_description,
    monitorable_occurence,
    TIMESTAMP(ts_call_start) AS ts_call_start,
    TIMESTAMP(ts_call_end) AS ts_call_end,
    TIMESTAMP(ts_occurrence) AS ts_occurrence,
    ts_load,
    year,
    month,
    day
FROM
    datalake_recupera_homolog_raw.historical_records
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
