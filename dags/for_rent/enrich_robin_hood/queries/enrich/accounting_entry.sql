SELECT
    id,
    id_external,
    id_source,
    id_payee,
    GET_JSON_OBJECT(metadata, '$.lead-id') as id_lead,
    GET_JSON_OBJECT(metadata, '$.house-id') as id_house,
    GET_JSON_OBJECT(metadata, '$.contract-id') as id_contract,
    GET_JSON_OBJECT(metadata, '$.offer-id') as id_offer,
    cost_center_code,
    source_bill_item,
    description,
    type,
    locale,
    due_amount,
    accrual_year_month,
    accounting_year_month,
    dt_occurrence,
    ts_blocked,
    ts_created
FROM
    datalake_robin_hood_clean.accounting_entry