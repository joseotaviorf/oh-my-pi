SELECT
    NULLIF(belnr, '') AS id_transaction,
    NULLIF(bukrs, '') AS id_company,
    NULLIF(zuonr, '') AS id_finance_entity,
    NULLIF(zztrx_entryid, '') AS id_finance_entity_entry,
    NULLIF(xref1_hd, '') AS id_business_entity,
    NULLIF(kidno, '') AS id_external_payment,
    NULLIF(buzei, '') AS id_line,
    NULLIF(xref2_hd, '') AS source_client,
    NULLIF(gjahr, '') AS fiscal_year,
    NULLIF(zzref_per, '') AS accrual_year_month,
    NULLIF(dmbtr, '') AS document_amount,
    COALESCE(NULLIF(kunnr,''), NULLIF(lifnr,'')) AS account_shortname,
    NULLIF(hkont, '') AS account_number,
    NULLIF(zzbp_type, '') AS user_type,
    NULLIF(zzacc_rule, '') AS accounting_rule,
    CASE
        WHEN shkzg = 'S' THEN 'Debit'
        WHEN shkzg = 'H' THEN 'Credit'
        ELSE 'Unknown'
    END AS indicator,
    NULLIF(sgtxt, '') AS memo_line,
    NULLIF(kostl, '') AS cost_center_code,
    COALESCE(NULLIF(fkber, ''), NULLIF(tcode, '')) AS location_profit_code,
    NULLIF(prctr, '') AS managerial_code,
    NULLIF(bschl, '') AS posting_key,
    NULLIF(monat, '') AS posting_period,
    NULLIF(blart, '') AS accounting_type,
    COALESCE(NULLIF(ZZMEMOITEM, ''),NULLIF(bktxt, '')) AS memo,
    NULLIF(usnam, '') AS created_by,
    NULLIF(xblnr, '') AS xblnr,
    NULLIF(waers, '') AS currency_code,
    NULLIF(ZZMEMOCAB, '') AS comments,
    NULLIF(zzhash, '') AS hash,
    TO_DATE(bldat, 'yyyyMMdd') AS dt_tax,
    TO_DATE(budat, 'yyyyMMdd') AS dt_accrual,
    TO_DATE(cpudt, 'yyyyMMdd') AS dt_created,
    year,
    month,
    day
FROM
    datalake_sap_4hana_raw.journal_entries
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}

