SELECT
    id,
    type,
    rev,
    revend          AS rev_end,
    revtype         AS rev_type,
    invoice,
    propose,
    amount,
    created_at_mod  AS mod_created_at,
    invoice_mod     AS mod_invoice,
    propose_mod     AS mod_propose,
    amount_mod      AS mod_amount,
    type_mod        AS mod_type,
    created_at      AS ts_created

FROM
    datalake_rental_guarantee_platform_raw.entry_aud
