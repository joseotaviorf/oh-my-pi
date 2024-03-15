WITH distributions_timeline AS (
    WITH contracts AS (
        SELECT
            id_customer AS document,
            id_contract
        FROM
            datalake_recupera.snapshot_daily_debts
        WHERE
            id_creditor IN (3,5)
        GROUP BY ALL
    )
    SELECT
        c.document,
        dd.id_contract,
        dd.partner AS team,
        dd.dt_start_interval,
        dd.dt_end_interval
    FROM
        datalake_recupera.changes_debts_distribution AS dd
    LEFT JOIN
        contracts AS c
            ON c.id_contract = dd.id_contract
    WHERE
        dd.creditor = 'IQ QuintoCred'
),

collection_recovery_team AS (
    SELECT
        DATE(DATE_TRUNC("MONTH",FNI.dt_paid)) AS dt_month_paid,
        FN.sk_debtor AS document,
        CASE
        WHEN FN.id_operator IN (
                                'DAMARIS',
                                'BRUNAQ',
                                'DBRASSAN',
                                'ELIDIANE',
                                'ERICKOTO',
                                'GSLIMA',
                                'HLIMA',
                                'IGNUNES',
                                'JMOURA',
                                'JENIFFER',
                                'JOHANNC',
                                'LRISSI',
                                'MSANTOS',
                                'TAYNAPIN',
                                'THAYANEC',
                                'THIFANYM',
                                'BKARINE',
                                'DBRASSANINI') THEN "TIME INTERNO"
        WHEN FN.id_operator = "PASCHOWS" THEN "PASCH"
        WHEN FN.id_operator = "IAFWS" THEN "IAF"
        ELSE "TIME NAO LOCALIZADO"
        END AS team,
        ROUND(SUM(FNI.MAIN_AMOUNT),2) AS original_value,
        ROUND(SUM(FNI.paid_amount),2) AS paid_amount
    FROM
        dw_collection_recovery.fact_negotiation_installment AS FNI
    LEFT JOIN
        dw_collection_recovery.fact_negotiation AS FN
            ON FNI.sk_negotiation = FN.sk_negotiation
WHERE
    FNI.dt_paid >= "2023-08-01"
    AND FN.creditor = 'IQ QuintoCred'
GROUP BY dt_month_paid, document, team
HAVING
    team <> "TIME NAO LOCALIZADO"
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY dt_month_paid, document ORDER BY original_value DESC ) = 1
)

SELECT
    cw.id_propose AS sk_propose,
    cw.name,
    cw.document,
    cw.mob,
    cw.type_description_array,
    cw.major_type,
    rt.team AS team_negotiation,
    dt.team AS team_distribution,
    cw.total_delinquency_amount,
    cw.total_original_value,
    cw.total_amount_paid,
    cw.amount_paid_added,
    cw.total_open_amount,
    cw.is_finished_array,
    cw.has_month_eviction,
    cw.dt_ended_propose,
    cw.dt_base,
    cw.dt_paid_array
FROM
    datalake_velo.collections_wallet AS cw
LEFT JOIN
    collection_recovery_team AS rt
        ON rt.document = cw.document
        AND rt.dt_month_paid = DATE(DATE_TRUNC("MONTH",cw.dt_base))
LEFT JOIN
    distributions_timeline AS dt
        ON dt.document = cw.document
        AND cw.dt_base >= dt.dt_start_interval
        AND (
            cw.dt_base <= dt.dt_end_interval
            OR dt.dt_end_interval IS NULL
        )
