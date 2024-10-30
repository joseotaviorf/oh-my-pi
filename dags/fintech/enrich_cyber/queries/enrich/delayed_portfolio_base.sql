WITH deduplicate_records_delinquent_master AS (
    SELECT
        contract_group,
        creditor,
        id_contract,
        id_client,
        debtor_name,
        segmentation_queue,
        commission_queue,
        agreement_queue,
        digital_channel_queue,
        eviction_queue,
        credit_denial_queue,
        olos_dialer_label,
        id_agency
    FROM datalake_cyber_clean.delinquent_master
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, contract_group ORDER BY MAKE_DATE(year, month, day) DESC) = 1
)
SELECT
    dm.id_contract,
    dm.id_client,
    b.id_invoice,
    a.id_agreement,
    ha.id_invoice AS id_agreement_invoice,
    ai.installment_number,
    dm.contract_group,
    dm.creditor AS product,
    dm.debtor_name,
    b.purpose,
    b.invoice_status,
    b.retsuko_status,
    a.status AS negotiation_status,
    ai.status AS agreement_installment_status,
    IF(a.id_agreement IS NULL, FALSE, TRUE) AS has_negotiation,
    dm.segmentation_queue,
    dm.commission_queue,
    dm.agreement_queue,
    dm.digital_channel_queue,
    dm.eviction_queue,
    dm.credit_denial_queue,
    dm.olos_dialer_label,
    dm.id_agency AS agency,
    a.number_of_installments,
    b.main_amount,
    a.total_negotiated_amount_with_fees,
    b.ts_installment_due AS ts_invoice_due,
    ai.ts_due_installment AS ts_due_agreement_installment
FROM
    deduplicate_records_delinquent_master AS dm
INNER JOIN
    datalake_cyber_clean.contracts AS c
     ON dm.id_contract = c.id_contract AND dm.contract_group = c.contract_group
LEFT JOIN
    datalake_cyber_clean.bill AS b
        ON dm.id_contract = b.id_contract AND dm.contract_group = b.contract_group AND b.invoice_or_entry = "Invoice"
LEFT JOIN
    datalake_cyber_clean.contracts_agreements AS ca
        ON dm.id_contract = ca.id_contract AND dm.contract_group = ca.contract_group
LEFT JOIN
    datalake_cyber_clean.historical_agreements AS ha
        ON ca.id_agreement = ha.id_agreement
LEFT JOIN
    datalake_cyber_clean.agreements AS a
        ON ca.id_agreement = a.id_agreement
LEFT JOIN
    datalake_cyber_clean.agreement_installments AS ai
        ON ai.id_agreement = ca.id_agreement
WHERE b.retsuko_status = "open"
