WITH sap_entity AS (
    SELECT
        *
    FROM
        datalake_retsuko_clean.sap_entity
    WHERE
        version IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity ORDER BY ts_updated DESC) = 1
),

accounting_version AS (
    SELECT DISTINCT
        e.id_external AS id_entry,
    CASE
        WHEN se_1.id_finance_entity IS NOT NULL THEN se_1.version
        WHEN se_2.id_finance_entity IS NOT NULL THEN se_2.version
        WHEN se_1.id_finance_entity IS NULL AND se_2.id_finance_entity IS NULL AND c.landlord_legal_person = 'physical' AND DATE(e.ts_created) < DATE('2024-03-18') THEN 'v1'
        WHEN se_1.id_finance_entity IS NULL AND se_2.id_finance_entity IS NULL AND c.landlord_legal_person = 'physical' AND DATE(e.ts_created) >= DATE('2024-03-18') THEN 'v2'
        WHEN se_1.id_finance_entity IS NULL AND se_2.id_finance_entity IS NULL AND c.landlord_legal_person = 'juridical' AND DATE(e.ts_created) < DATE('2024-06-10') THEN 'v1'
        WHEN se_1.id_finance_entity IS NULL AND se_2.id_finance_entity IS NULL AND c.landlord_legal_person = 'juridical' AND DATE(e.ts_created) >= DATE('2024-06-10') THEN 'v2'
        ELSE 'ERROR'
    END AS accounting_version
    FROM
        datalake_retsuko_clean.entry AS e
    LEFT JOIN
        datalake_retsuko_clean.contract AS c
            ON e.id_contract = c.id
    LEFT JOIN
        datalake_retsuko_clean.invoice AS i
            ON e.id_invoice = i.id
    LEFT JOIN
        sap_entity AS se_1
            ON e.id_external = se_1.id_finance_entity
    LEFT JOIN
        sap_entity AS se_2
            ON i.id_external = se_2.id_finance_entity
)

SELECT
    e.id,
    e.id_external,
    e.id_invoice,
    e.id_contract,
    e.id_from_account,
    e.id_to_account,
    e.id_external_reversed_entry,
    e.id_audit,
    e.accounting_transaction_identifier,
    av.accounting_version,
    ROUND(CASE
          WHEN af.type = 'contract'
              AND at.type <> 'contract' THEN -1.0 * e.amount
      ELSE e.amount
      END, 2) AS amount,
    e.bill_item,
    e.description,
    e.producer,
    e.status,
    e.accrual_year_month,
    e.due_year_month,
    e.ts_created,
    e.ts_synced,
    e.ts_retsuko_updated,
    e.ts_database_transaction
FROM
    datalake_retsuko_clean.entry e
LEFT JOIN
    datalake_retsuko_clean.account AS af
        ON e.id_from_account = af.id
LEFT JOIN
    datalake_retsuko_clean.account AS at
        ON e.id_to_account = at.id
LEFT JOIN
    datalake_retsuko_clean.contract c
        ON c.id = e.id_contract
LEFT JOIN
    accounting_version AS av
        ON e.id_external = av.id_entry
