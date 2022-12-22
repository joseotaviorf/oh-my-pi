SELECT
    id_trasaction AS sk_transaction,
    project,
    status,
    transaction_type,
    transaction_purpose,
    installment,
    total_expected_installments,
    is_project_receivable_created,
    is_project_receivable_greater_than_payable,
    NOW() AS ts_load
FROM
    datalake_velo.transaction_entries
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
