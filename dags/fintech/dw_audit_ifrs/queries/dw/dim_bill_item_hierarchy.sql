WITH invoice_repair_amounts AS (
    SELECT
        sk_invoice,
        SUM(CASE WHEN bill_item_name = 'repair offboarding' THEN bill_item_due_amount ELSE 0 END) AS repair_offboarding,
        SUM(CASE WHEN bill_item_name = 'residential protection 5A acquittance' THEN bill_item_due_amount ELSE 0 END) AS residential_protection_5a_acquittance,
        SUM(CASE WHEN bill_item_name = 'residential protection 5A fund transfer' THEN bill_item_due_amount ELSE 0 END) AS residential_protection_5a_fund_transfer
    FROM
        dw_losses.dim_bill_items
    WHERE
        bill_item_name IS NOT NULL
    GROUP BY
        sk_invoice
)
SELECT DISTINCT
    sk_invoice,
    CASE
        WHEN repair_offboarding > 0
            OR residential_protection_5a_acquittance > 0
            OR residential_protection_5a_fund_transfer > 0
            THEN 'repair_invoice'
        ELSE 'guarantee_invoice'
    END AS invoice_hierarchy
FROM
    invoice_repair_amounts
