SELECT
    id,
    credit_line_id AS id_credit_line,
    deal_id AS id_deal,
    uuid,
    draw_number,
    amount,
    processing_date AS dt_processing,
    target_disbursement_date AS dt_target_disbursement,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_lending_raw.credit_line_draw
