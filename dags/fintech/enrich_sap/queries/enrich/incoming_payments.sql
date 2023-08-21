WITH cte_most_recent AS (
    SELECT
        id_transaction,
        MAX(MAKE_DATE(year, month, day)) AS dt_last_updated
    FROM
        datalake_pas_clean.incoming_payments
    GROUP BY 1
)

SELECT DISTINCT
    t1.id_transaction,
    t1.id_business_entity,
    t1.id_financial_entity,
    t1.id_external_payment,
    t1.id_user_sign,
    t1.legacy_uuid,
    t1.uuid,
    t1.document_entry,
    t1.memo,
    t1.source_document_number,
    t1.series,
    t1.source_client,
    t1.transaction_type,
    t1.updated_by,
    t1.accrual_year_month,
    t1.loc_total,
    t1.dt_document,
    t1.dt_tax,
    t1.dt_reference,
    t1.dt_due,
    t1.dt_created,
    t1.dt_updated,
    t1.year,
    t1.month,
    t1.day
FROM
    datalake_pas_clean.incoming_payments AS t1
RIGHT JOIN
    cte_most_recent AS cte
    ON cte.id_transaction = t1.id_transaction
    AND cte.dt_last_updated = MAKE_DATE(t1.year, t1.month, t1.day)
