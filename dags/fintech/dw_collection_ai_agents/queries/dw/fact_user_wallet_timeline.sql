WITH user_contract_map AS (
    WITH sources_id_user AS (
        SELECT DISTINCT
            sk_contract AS id_contract,
            sk_user AS id_user,
            'fact' AS source
        FROM
            dw_rent.fact_contract_people fc
        LEFT JOIN datalake_ebdb_clean.contract ebdb
            ON ebdb.id = fc.sk_contract
        WHERE fc.sk_user > 0
        AND fc.contract_role IN ('tenant','dweller')

        UNION ALL

        SELECT
            DISTINCT id AS id_contract,
            id_user,
            'ebdb' AS source
        FROM
            datalake_ebdb_clean.contract
    ),
    unique_list AS (
          SELECT DISTINCT
            id_contract,
            id_user
        FROM
            sources_id_user
    )
    SELECT
        dc.dt_start,
        dc.dt_annulment,
        dc.status,
        u.*,
        du.nome,
        du.cpf,
        du.email,
        du.telefone_principal,
        du.data_nascimento
    FROM
        unique_list AS u
    LEFT JOIN
        dw_public.dim_user AS du
        ON du.id = u.id_user
    LEFT JOIN
        dw_rent.dim_contract AS dc
        ON dc.sk_contract = u.id_contract
    WHERE dc.status <> 'Cancelado'
),
answer_sheet AS (
    SELECT
        dt_reference,
        sk_contract,
        reference_contract_status,
        max_delay_contaminated_contract_t2,
        wallet_overdue_t2,
        overdue_recovered_amount_t2,
        n_invoices_in_wallet,
        wallet,
        recovered_amount,
        array_open_invoices,
        array_paid_invoices,
        array_negotiated_invoices,
        recovered_amount + LEAD(recovered_amount, 1) OVER (PARTITION BY sk_contract ORDER BY dt_reference) AS recovery_next_2_days,
        overdue_recovered_amount_t2 + LEAD(overdue_recovered_amount_t2, 1) OVER (PARTITION BY sk_contract ORDER BY dt_reference) AS overdue_recovered_amount_t2_next_2_days
    FROM
        dw_collections_segmentation.fact_contract_wallet_timeline
    WHERE dt_reference BETWEEN DATE_TRUNC('MONTH', DATE_ADD(DATE('{load_start_date}'), -30)) AND DATE_ADD(DATE('{load_end_date}'), 1)
    ),
clean_sheet AS (
    -- The goal of this filter is to make sure that we are not considering contracts that are not active without debt, meaning a current ended contract => does not exist anymore
    SELECT
        *
    FROM
        answer_sheet
    WHERE
        reference_contract_status = 'Ativo'
        OR wallet > 0
    ),
user_timeline AS (
    SELECT
        a.*,
        u.id_user
    FROM
        clean_sheet AS a
    LEFT JOIN user_contract_map AS u
        ON u.id_contract = a.sk_contract
    WHERE u.id_user IS NOT NULL
    )

SELECT
    id_user AS sk_user,
    MAX(max_delay_contaminated_contract_t2) AS max_delay_contaminated_contract_t2,
    SUM(n_invoices_in_wallet) AS invoices_in_wallet,
    SUM(wallet) AS user_wallet,
    SUM(recovered_amount) AS user_payment,
    SUM(wallet_overdue_t2) AS user_wallet_overdue_t2,
    SUM(overdue_recovered_amount_t2) AS user_overdue_recovered_amount_t2,
    SUM(recovery_next_2_days) AS user_payment_w_2,
    SUM(overdue_recovered_amount_t2_next_2_days) AS user_overdue_recovered_amount_t2_w_2,
    COUNT(sk_contract) AS n_contracts,
    COUNT(CASE WHEN reference_contract_status = 'Ativo' THEN sk_contract ELSE NULL END) AS active_contracts,
    COUNT(CASE WHEN reference_contract_status = 'Finalizado' THEN sk_contract ELSE NULL END) AS ended_contracts,
    ARRAY_AGG(sk_contract) AS contracts,
    ARRAY_AGG(CASE WHEN recovered_amount > 0 THEN sk_contract ELSE NULL END) AS contracts_w_recovery,
    FLATTEN(COLLECT_LIST(array_open_invoices)) AS array_open_invoices,
    FLATTEN(COLLECT_LIST(array_paid_invoices)) AS array_paid_invoices,
    FLATTEN(COLLECT_LIST(array_negotiated_invoices)) AS array_negotiated_invoices,
    dt_reference
FROM
    user_timeline
WHERE
    dt_reference BETWEEN DATE_TRUNC('MONTH', DATE_ADD(DATE('{load_start_date}'), -30)) AND DATE_ADD(DATE('{load_end_date}'), 1)
GROUP BY 1,18
