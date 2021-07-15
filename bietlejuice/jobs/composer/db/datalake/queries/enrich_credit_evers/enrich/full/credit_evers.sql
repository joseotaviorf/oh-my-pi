WITH filtering_invoices AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY id_contract_ebdb ORDER BY dt_contract_updated DESC) AS listing_rank
    FROM
        datalake_credit_evers.credit_evers_audit
)
SELECT 
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    months_of_contract,
    contract_mob_number,
    contract_ever_number,
    is_ever,
    num_overs_in_mob_window,
    total_due_amount_in_mob_window,
    num_total_overs,
    total_due_amount,
    ts_signature,
    dt_contract_updated
FROM 
    filtering_invoices
WHERE
    listing_rank = 1