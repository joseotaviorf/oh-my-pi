-- Utility-bill CAP rows the Recon squad marked to ignore (account_type = supplier).
SELECT
    TRY_CAST(NULLIF(TRIM(sk_contract), '') AS BIGINT) AS sk_contract,
    NULLIF(TRIM(id_entry), '') AS id_entry,
    NULLIF(TRIM(id_invoice), '') AS id_invoice,
    TRIM(conta) AS recon_account,
    LOWER(TRIM(account_type)) AS account_type,
    TRIM(entry_status) AS entry_status,
    TRIM(motivo_exclusao) AS exclusion_reason,
    TRIM(classificacao) AS classification_label,
    TRY_CAST(
        REPLACE(TRIM(CAST(due_amount AS STRING)), ',', '.') AS DECIMAL(18, 2)
    ) AS due_amount,
    TRY_CAST(entry_created_date AS DATE) AS entry_created_date
FROM
    datalake_gsheets_raw.recon_ignored_cap_consumption
WHERE
    LOWER(TRIM(account_type)) = 'supplier'
    AND TRY_CAST(NULLIF(TRIM(sk_contract), '') AS BIGINT) IS NOT NULL
    AND TRY_CAST(
        REPLACE(TRIM(CAST(due_amount AS STRING)), ',', '.') AS DECIMAL(18, 2)
    ) IS NOT NULL
    AND TRY_CAST(entry_created_date AS DATE) IS NOT NULL
