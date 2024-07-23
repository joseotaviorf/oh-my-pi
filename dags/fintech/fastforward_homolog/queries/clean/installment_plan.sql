SELECT
    id,
    number_of_installments as installments,
    interest_rate,
    min_installment_value,
    created_at as ts_created,
    updated_at as ts_updated
FROM
    datalake_fastforward_homolog_raw.installment_plan
