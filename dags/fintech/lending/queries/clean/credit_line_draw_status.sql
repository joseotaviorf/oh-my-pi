SELECT
    id,
    credit_line_draw_id AS id_credit_line_draw,
    status,
    created_at AS ts_created
FROM
    datalake_lending_raw.credit_line_draw_status
