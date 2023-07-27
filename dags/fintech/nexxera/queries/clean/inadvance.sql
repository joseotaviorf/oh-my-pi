SELECT
    registration_type,
    group_name,
    group_cnpj,
    constant_acquirers_number,
    total_records_number,
    total_sale_installments_value,
    total_advance_summaries_value,
    total_credit_adjustments_value,
    total_debit_adjustments_value,
    total_offset_adjustments_value,
    total_legacy_summary_installments_value,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.inadvance
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
