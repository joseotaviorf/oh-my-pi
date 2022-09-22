SELECT
    transaction_id_transid AS id_transaction,
    line_id_line_id AS id_line,
    business_entity_id_u_businessentityid AS id_business_entity,
    finance_entity_entry_id_u_financeentityentryid AS id_finance_entity_entry,
    financial_entity_id_u_financeentityid AS id_finance_entity,
    document AS id_document,
    cost_center_ocrcode2 AS cost_center_code,
    contraact_contraact AS contra_act,
    location_profitcode AS location_profit_code,
    managerial_ocrcode3 AS managerial_code,
    memo_linememo AS memo_line,
    number_number AS source_document_number,
    series_series AS series,
    account_account AS account,
    account_shortname AS account_shortname,
    transaction_type_transtype AS transaction_type,
    credit,
    debit,
    accrualdate_u_accrualdate AS dt_accrual,
    duedate AS dt_due,
    refdate AS dt_reference,
    taxdate AS dt_tax,
    year,
    month,
    day
FROM
    datalake_sap_raw.invoice_lines
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}
