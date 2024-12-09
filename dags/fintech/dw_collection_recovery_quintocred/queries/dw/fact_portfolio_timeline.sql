WITH distributions_timeline AS (
    WITH contracts AS (
        SELECT
            CAST(id_customer AS INT) AS document,
            id_contract
        FROM
            datalake_recupera.snapshot_daily_debts
        WHERE
            id_creditor IN (3,5)
        GROUP BY id_customer, id_contract
    )
    SELECT DISTINCT
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
    QUALIFY ROW_NUMBER() OVER (PARTITION BY dd.dt_start_interval ORDER BY
    CASE
        WHEN dd.partner = 'INTERNO VELO' THEN 1
        WHEN dd.partner = 'IAF' THEN 2
        WHEN dd.partner = 'PASCHOALOTTO' THEN 3
        WHEN dd.partner = 'BRBOTS' THEN 4
        WHEN dd.partner = 'DIGTECH' THEN 5
        ELSE 6
    END) = 1
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
        dw_collection_recovery_quintoandar.fact_negotiation_installment AS FNI
    LEFT JOIN
        dw_collection_recovery_quintoandar.fact_negotiation AS FN
            ON FNI.sk_negotiation = FN.sk_negotiation
WHERE
    FNI.dt_paid >= "2023-08-01"
    AND FN.creditor = 'IQ QuintoCred'
GROUP BY dt_month_paid, document, team
HAVING
    team <> "TIME NAO LOCALIZADO"
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY dt_month_paid, document ORDER BY original_value DESC ) = 1
),

distinct_contract_customer AS (
    SELECT DISTINCT
        id_contract,
        id_customer
    FROM
        datalake_recupera_clean.contracts
),

operational_records AS (
    SELECT DISTINCT
        id_customer,
        distributor_code AS distributor,
        ts_customer_status_last_update,
        MAKE_DATE(year, month, day) AS dt_snapshot
    FROM
        datalake_recupera_clean.operational_records
    WHERE
        id_creditor IN ('3','5') -- filter quintocred
        AND MAKE_DATE(year, month, day) BETWEEN DATE_TRUNC("month", CURRENT_DATE - INTERVAL "48" MONTH) AND CURRENT_DATE - INTERVAL "1" DAY
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_customer, MAKE_DATE(year, month, day) ORDER BY ts_last_update DESC) = 1
),

responsible_for_contract AS (
    SELECT DISTINCT
        c.id_contract,
        ors.distributor,
        ors.dt_snapshot
    FROM
        operational_records As ors
    LEFT JOIN
        distinct_contract_customer AS c
            ON ors.id_customer = c.id_customer
    QUALIFY ROW_NUMBER() OVER(PARTITION BY c.id_contract, ors.dt_snapshot ORDER BY ors.ts_customer_status_last_update DESC) = 1
)

SELECT DISTINCT
    cw.id_propose AS sk_propose,
    cw.name,
    cw.document,
    cw.mob,
    cw.type_description_array,
    cw.major_type,
    cw.monthly_major_type,
    rc.distributor,
    rt.team AS team_negotiation,
    dt.team AS team_distribution,
    cw.lead_time_major_type,
    cw.lead_time_propose,
        CASE
            WHEN cw.lead_time_major_type <= 30       THEN '1)001-030'
            WHEN cw.lead_time_major_type <=60        THEN '2)031-060'
            WHEN cw.lead_time_major_type <=90        THEN '3)061-090'
            WHEN cw.lead_time_major_type <=120       THEN '4)091-120'
            WHEN cw.lead_time_major_type <=150       THEN '5)121-150'
            WHEN cw.lead_time_major_type <=180       THEN '6)151-180'
            WHEN cw.lead_time_major_type <=210       THEN '7)181-210'
            WHEN cw.lead_time_major_type <=240       THEN '8)211-240'
            WHEN cw.lead_time_major_type <=270       THEN '9)241-270'
            WHEN cw.lead_time_major_type <=300       THEN '10)271-300'
            WHEN cw.lead_time_major_type <=330       THEN '11)301-330'
            WHEN cw.lead_time_major_type <=360       THEN '12)331-360'
            ELSE '13)>360'
        END AS major_type_aging_range,
        CASE
            WHEN cw.lead_time_propose <= 30       THEN '1)001-030'
            WHEN cw.lead_time_propose <=60        THEN '2)031-060'
            WHEN cw.lead_time_propose <=90        THEN '3)061-090'
            WHEN cw.lead_time_propose <=120       THEN '4)091-120'
            WHEN cw.lead_time_propose <=150       THEN '5)121-150'
            WHEN cw.lead_time_propose <=180       THEN '6)151-180'
            WHEN cw.lead_time_propose <=210       THEN '7)181-210'
            WHEN cw.lead_time_propose <=240       THEN '8)211-240'
            WHEN cw.lead_time_propose <=270       THEN '9)241-270'
            WHEN cw.lead_time_propose <=300       THEN '10)271-300'
            WHEN cw.lead_time_propose <=330       THEN '11)301-330'
            WHEN cw.lead_time_propose <=360       THEN '12)331-360'
            ELSE '13)>360'
        END AS propose_aging_range,
    cw.is_finished_array,
    cw.has_active_day_eviction,
    cw.has_active_month_eviction,
    cw.has_month_eviction,
    cw.dt_ended_propose,
    cw.dt_base,
    cw.dt_min_major_type,
    cw.dt_min_propose,
    cw.dt_paid_array
FROM
    datalake_collections_quintocred.collections_wallet AS cw
LEFT JOIN
    collection_recovery_team AS rt
        ON rt.document = cw.document
        AND rt.dt_month_paid = DATE(DATE_TRUNC("MONTH",cw.dt_base))
LEFT JOIN
    distributions_timeline AS dt
        ON CAST(dt.document AS INT) = CAST(cw.document AS INT)
        AND cw.dt_base >= dt.dt_start_interval
        AND (
            cw.dt_base <= dt.dt_end_interval
            OR dt.dt_end_interval IS NULL
        )
LEFT JOIN
    responsible_for_contract AS rc
        ON cw.id_propose = rc.id_contract
        AND cw.dt_base = rc.dt_snapshot
