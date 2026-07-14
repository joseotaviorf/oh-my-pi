SELECT
    id,
    credit_line_id AS id_credit_line,
    status,
    created_at AS ts_created
FROM
    datalake_lending_raw.credit_line_status
