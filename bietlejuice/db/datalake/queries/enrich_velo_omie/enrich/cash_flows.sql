WITH cte_most_recent AS (
    SELECT
        id_securities,
        GREATEST(MAX(ts_reconciliation), MAX(ts_created), MAX(ts_modified)) AS ts_last_modified
    FROM
        datalake_velo_omie_clean.cash_flows
    GROUP BY 1
)
SELECT
    cf.id_securities,
    cf.id_category,
    cf.id_integration_securities,
    cf.id_project,
    cf.id_seller,
    cf.id_group,
    cf.id_operation,
    cf.client_cpf_cnpj,
    cf.barcode,
    cf.bill_number,
    cf.contract_number,
    cf.tax_document_number,
    cf.service_order_number,
    cf.id_client,
    cf.id_buyer,
    cf.id_write_off,
    cf.id_bank_account,
    cf.id_contract,
    cf.id_moviment_bank_account,
    cf.id_moviment_bank_account_repeat,
    cf.id_invoice,
    cf.id_service_order,
    cf.id_securities_repeat,
    cf.id_payment_receipt,
    cf.id_installment,
    cf.securities_code,
    cf.eletronic_invoice_key,
    cf.origin,
    cf.status,
    cf.TYPE,
    cf.financial_nature,
    cf.alteration_user,
    cf.conciliation_user,
    cf.creation_user,
    cf.discount_value,
    cf.interest_value,
    cf.fine_value,
    cf.open_value,
    cf.net_value,
    cf.paid_value,
    cf.bank_account_movement_value,
    cf.securities_value,
    cf.pis_value,
    cf.cofins_value,
    cf.csll_value,
    cf.income_tax_value,
    cf.iss_value,
    cf.inss_value,
    cf.comments,
    cf.is_liquidated,
    cf.is_pis_retained,
    cf.is_cofins_retained,
    cf.is_csll_retained,
    cf.is_income_tax_retained,
    cf.is_iss_retained,
    cf.is_inss_retained,
    cf.dt_credit,
    cf.dt_issue,
    cf.dt_payment,
    cf.dt_predicted,
    cf.dt_register,
    cf.dt_due,
    cf.ts_modified,
    cf.ts_reconciliation,
    cf.ts_created,
    cf.year,
    cf.month,
    cf.day
FROM
    datalake_velo_omie_clean.cash_flows AS cf
RIGHT JOIN
    cte_most_recent AS cte
        ON cte.id_securities = cf.id_securities
        AND (
            cte.ts_last_modified = cf.ts_reconciliation
            OR cte.ts_last_modified = cf.ts_created
            OR cte.ts_last_modified = cf.ts_modified
        )
