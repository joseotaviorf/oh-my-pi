SELECT
    id,
    sales_flow_id AS id_sales_flow,
    payment_method,
    payment_model,
    down_payment_value,
    entry_amount,
    fgts_value,
    status,    
    fgts_doc_submission_finished_by,    
    fgts_payment_finished_by,
    is_down_payment_paid,
    payment_type,
    down_payment_paid_at AS ts_down_payment_paid,
    fgts_doc_submission_finished_at AS ts_fgts_doc_submission_finished,
    fgts_payment_finished_at AS ts_fgts_payment_finished,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.payment