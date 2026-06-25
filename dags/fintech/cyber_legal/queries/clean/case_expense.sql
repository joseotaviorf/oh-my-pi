WITH ranked_expenses AS (
    SELECT
        EXCASENO AS id_case,
        EXID AS id_expense,
        EXCOLLID AS id_attorney,
        EXCOLSUP AS id_supervisor_attorney,
        EXAGENCY AS id_agency,
        EXSTGID AS id_stage,
        EXLOTE AS id_lot,
        EXINVOICE AS id_invoice,
        EXCSTYPE AS case_type,
        EXCSSUBTYPE AS case_subtype,
        EXTYPE AS expense_type,
        EXSTYPE AS expense_subtype,
        EXDESC AS expense_description,
        EXIDESC AS invoice_description,
        EXSUPPLIER AS supplier_name,
        IF(EXAUTFLG = 'Y', TRUE, FALSE) AS is_authorized,
        IF(EXPAYEXP = 'Y', TRUE, FALSE) AS is_payment_made,
        IF(EXSTATUS = '1', TRUE, FALSE) AS is_recovered,
        IF(EXSTATUSAGN = '1', TRUE, FALSE) AS is_reimbursed,
        EXAMT AS expense_amount,
        EXAUTDT AS dt_authorized,
        EXDT AS dt_captured,
        EXINVOICEDT AS dt_invoice,
        EXDTRELCLI AS dt_recovered,
        EXDTRELAGN AS dt_reimbursed,
        EXDTUPD AS ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (PARTITION BY EXCASENO, EXID ORDER BY MAKE_DATE(year, month, day) DESC) AS row_number
    FROM
        datalake_cyber_legal_raw.caexpns
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_case,
    id_expense,
    id_attorney,
    id_supervisor_attorney,
    id_agency,
    id_stage,
    id_lot,
    id_invoice,
    case_type,
    case_subtype,
    expense_type,
    expense_subtype,
    expense_description,
    invoice_description,
    supplier_name,
    is_authorized,
    is_payment_made,
    is_recovered,
    is_reimbursed,
    expense_amount,
    dt_authorized,
    dt_captured,
    dt_invoice,
    dt_recovered,
    dt_reimbursed,
    ts_updated,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    ranked_expenses
WHERE
    row_number = 1
