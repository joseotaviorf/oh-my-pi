SELECT
    TransId AS id_trans,
    AcctCode AS acct_code,
    ContraAct AS contract_act,
    OcrCode2 AS ocr_code_2,
    ProfitCode AS profit_code,
    Ref1 AS ref_1,
    Ref2 AS ref_2,
    Ref3 AS ref_3,
    ShortName AS short_name,
    LineTotal AS line_total,
    DueDate AS dt_due,
    RefDate AS dt_ref,
    year,
    month,
    day
FROM
     datalake_ramo_sap_raw.razao_sap
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}