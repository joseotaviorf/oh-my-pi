SELECT
    ae.id,
    ae.id_external,
    ae.id_source,
    ae.id_payee,
    p.id_external AS id_payee_external,
    GET_JSON_OBJECT(ae.metadata, '$.lead-id') AS id_lead,
    GET_JSON_OBJECT(ae.metadata, '$.house-id') AS id_house,
    GET_JSON_OBJECT(ae.metadata, '$.contract-id') AS id_contract,
    GET_JSON_OBJECT(ae.metadata, '$.offer-id') AS id_offer,
    ae.cost_center_code,
    ae.source_bill_item,
    ae.description,
    ae.type,
    ae.locale,
    aes.source_name,
    ae.due_amount,
    ae.accrual_year_month,
    ae.accounting_year_month,
    ae.dt_occurrence,
    ae.ts_blocked,
    ae.ts_created
FROM
    datalake_robin_hood_clean.accounting_entry ae 
LEFT JOIN 
    datalake_robin_hood_clean.payee p 
        ON p.id = ae.id_payee
LEFT JOIN 
    datalake_robin_hood_clean.accounting_entry_source aes
        ON ae.id_source = aes.id