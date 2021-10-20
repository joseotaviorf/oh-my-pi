SELECT
    id AS id_mortgage,
    sales_flow_id AS id_sales_flow,
    status,
    bank,
    credit_model,
    credit_status,
    bank_fee,
    institution_choice_reason,
    credit_letter,
    mortgage_pendency,
    credit_start_date AS dt_credit_started,
    credit_end_date AS dt_credit_ended,
    bank_start_date AS dt_bank_started,
    start_date AS dt_started,
    end_date AS dt_ended,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_sales_flow_raw.mortgage
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}