WITH bill_items_cohort_rules AS (
    SELECT
        id_invoice AS sk_invoice,
        id_contract AS sk_contract,
        bi.bill_item_cluster_name,
        bi.due_amount,
        SUM(bi.value_sign_bill_item) as value_bill_item_cluster,
        bi.dt_created,
        bi.dt_due,
        bi.dt_paid,
        bi.dt_canceled
    FROM datalake_retsuko.bill_items AS bi
    WHERE bi.payment_status IN ('open','paid','canceled')
        AND bi.due_amount <= 0
    GROUP BY 1,2,3,4,6,7,8,9
)
SELECT
    sk_invoice,
    sk_contract,
    id_lvl_1 AS sk_junk_bill_items_cluster,
    value_bill_item_cluster,
    due_amount,
    GREATEST(12*(YEAR(current_date)-YEAR(dt_created))+(MONTH(current_date)-MONTH(dt_created)),0) AS mobs_possible_invoice_by_created_date,
    GREATEST(12*(YEAR(current_date)-YEAR(dt_due))+(MONTH(current_date)-MONTH(dt_due)),0) AS mobs_possible_invoice_by_due_date,
    IF(dt_paid IS NOT NULL,
      GREATEST(12*(YEAR(dt_paid)-YEAR(dt_created))+(MONTH(dt_paid)-MONTH(dt_created)),0),
      NULL
    ) AS mob_paid_by_created_date,
    IF(dt_canceled IS NOT NULL,
      GREATEST(12*(YEAR(dt_canceled)-YEAR(dt_created))+(MONTH(dt_canceled)-MONTH(dt_created)),0),
      NULL
    ) AS mob_canceled_by_created_date,
    IF(dt_paid IS NOT NULL,
      GREATEST(12*(YEAR(dt_paid)-YEAR(dt_due))+(MONTH(dt_paid)-MONTH(dt_due)),0),
      NULL
    ) AS mob_paid_by_due_date,
    IF(dt_canceled IS NOT NULL,
      GREATEST(12*(YEAR(dt_canceled)-YEAR(dt_due))+(MONTH(dt_canceled)-MONTH(dt_due)),0),
      NULL
    ) AS mob_canceled_by_due_date,
    GREATEST(12*(YEAR(dt_due)-YEAR(dt_created))+(MONTH(dt_due)-MONTH(dt_created)),0) AS  mob_due_by_created_date,
    GREATEST(12*(YEAR(dt_due)-YEAR(dt_due))+(MONTH(dt_due)-MONTH(dt_due)),0) AS  mob_due_by_due_date,
    DATE_TRUNC('MONTH', dt_due) AS ts_safra_per_dt_due,
    DATE_TRUNC('MONTH', dt_created) AS ts_safra_per_dt_created
FROM
    bill_items_cohort_rules AS cr
LEFT JOIN datalake_retsuko.retsuko_junk AS jk
    ON jk.desc_master_type = 'bill_item_cluster_name'
    AND jk.desc_lvl_1 = cr.bill_item_cluster_name
