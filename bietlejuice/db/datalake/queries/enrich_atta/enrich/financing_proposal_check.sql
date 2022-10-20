WITH cte_most_recent AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_updated
    FROM
        datalake_atta_clean.financing_proposal_check
    GROUP BY 1
)
SELECT
    fpc.id,
    fpc.id_proposal_product,
    fpc.id_confirmed_user,
    fpc.id_included_user,
    fpc.house_sale_value,
    fpc.down_payment_own_resources_value,
    fpc.fgts_down_payment_value,
    fpc.financing_value,
    fpc.bank_valuation_value,
    fpc.bank_valuation_fee_value,
    fpc.itbi_value,
    fpc.installments_quantity,
    fpc.financing_fee,
    fpc.payment_sale_value,
    fpc.has_seller_debt_payment,
    fpc.seller_debt_payment_value,
    fpc.channel,
    fpc.is_confirmed,
    fpc.ts_updated,
    fpc.ts_confirmation,
    fpc.ts_inclusion,
    fpc.ts_seller_debt_payment
FROM
    datalake_atta_clean.financing_proposal_check AS fpc
RIGHT JOIN
    cte_most_recent AS cte
        ON cte.id = fpc.id
        AND cte.ts_updated = fpc.ts_updated
