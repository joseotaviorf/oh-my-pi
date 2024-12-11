WITH
recovered_value AS (
    SELECT
        DATE(dt_paid) AS Data,
        id_operator AS operator,
        COUNT(DISTINCT i.sk_negotiation) AS payments,
        ROUND(SUM(i.paid_amount), 2) AS recovered_value
    FROM
        dw_collection_recovery_quintocred.fact_negotiation f
    LEFT JOIN
        dw_collection_recovery_quintocred.fact_negotiation_installment i
        ON i.sk_negotiation = f.sk_negotiation
    WHERE
        DATE(dt_paid) >= DATE('2024-04-01')
        AND f.creditor = 'IQ QuintoCred'
    GROUP BY 1, 2
    ORDER BY 1
),
operators AS (
    SELECT
        a.date,
        d.login,
        d.sk_operator
    FROM
        datalake_quintoandar.aux_date a
    CROSS JOIN
        dw_operator_performance.dim_operator d
    WHERE DATE(a.date) >= DATE('2024-01-01')
    AND company = 'QUINTOANDAR'
)

SELECT
    o.sk_operator,
    o.login AS operator,
    MAX(r.recovered_value) AS recovered_value,
    o.date AS dt_reference,
    YEAR(o.date) AS year,
    MONTH(o.date) AS month,
    DAY(o.date) AS day
FROM
    datalake_quintoandar.aux_date d
LEFT JOIN
    operators o
    ON o.date = d.date
LEFT JOIN recovered_value r
    ON CAST(r.data AS date) = o.date AND r.operator = o.login
WHERE
    o.login IN ('BKARINE',
                'BRUNAQ',
                'DBRASSAN',
                'ELIANEM',
                'EVELYNT',
                'HLIMA',
                'IGNUNES',
                'JCARVALH',
                'JMOURA',
                'MSANTOS',
                'THAYANEC',
                'THIFANYM',
                'ANARPACH',
                'ANDERSAN',
                'ANDREMAC',
                'CRISBENE',
                'DANILOP',
                'ELAINEC',
                'EMILISIL',
                'EVERTONB',
                'ISABELES',
                'JANAINAA',
                'JUBITTEN',
                'KATHLEN',
                'LOUIZY',
                'MARIAVS',
                'RAYLENE')
    AND DATE(d.date) >= DATE('2024-04-01')
    AND DATE(d.date) <= DATE(DATE_ADD(CURRENT_DATE,-1))
GROUP BY 1, 2, 4, 5, 6
ORDER BY 1, 2
