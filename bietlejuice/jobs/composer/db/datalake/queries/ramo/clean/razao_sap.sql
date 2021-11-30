SELECT
    Line_ID AS id_line,
    TransId AS id_trans,
    Account AS account,
    AcctName AS account_name,
    ContraAct AS contract_act,
    CtrActName AS ctr_act_name,
    OcrCode2 AS ocr_code_2,
    ProfitCode AS profit_code,
    Ref1 AS ref_1,
    Ref2 AS ref_2,
    Ref3 AS ref_3,
    ShortName AS short_name,
    linememo AS line_memo,
    LineTotal AS line_total,
    CreateDate AS dt_created,
    DueDate AS dt_due,
    RefDate AS dt_ref,
    TaxDate AS dt_tax,
    year,
    month,
    day
FROM
     datalake_ramo_raw.razao_sap
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}