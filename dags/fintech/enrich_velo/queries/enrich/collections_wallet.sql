WITH delinquency_end AS (
    SELECT DISTINCT
        id_delinquency,
        COALESCE(dt_paid, dt_updated) AS dt_updated
    FROM
        datalake_velo.delinquency_timeline
    WHERE
        is_finished
),
timeline_base AS (
    SELECT
        t.*,
        COALESCE(t.dt_paid, t.dt_updated) AS dt_updated_paid,
        de.dt_updated AS dt_delinquency_last_register
    FROM
        datalake_velo.delinquency_timeline t
    LEFT JOIN
        delinquency_end de
            ON de.id_delinquency = t.id_delinquency
),
cte_timeline_daily AS (
    SELECT
        d.`date`,
        d.month_start,
        t.id_delinquency,
        MAX(t.dt_updated_paid) AS dt_updated
    FROM
        datalake_quintoandar.aux_date AS d
    LEFT JOIN
        timeline_base AS t
            ON IF(t.is_finished, d.`date` >= t.dt_updated_paid AND d.`date` <= LAST_DAY(t.dt_updated_paid), d.`date` >= t.dt_updated_paid AND d.`date` < t.dt_delinquency_last_register)
    WHERE
        d.`date` > DATE('2020-01-01')
        AND d.`date` < CURRENT_DATE()
    GROUP BY 1,2,3
    ORDER BY 3,1
),
timeline AS (
    SELECT
        td.`date`,
        pp.name,
        pp.document,
        CASE
            WHEN is_legacy_agreement THEN INT(months_between(td.month_start, t.dt_due))
            WHEN t.type_description = 'SIGNATURE' AND t.dt_created >= DATE('2024-02-01') THEN INT(months_between(td.month_start, t.dt_due))
            ELSE INT(months_between(td.month_start, t.dt_created))
        END AS mob_delinquency,
        t.*,
        IF(td.`date` <> COALESCE(t.dt_paid, t.dt_updated), 0.00, t.amount_paid_added) AS amount_paid_added_fixed
    FROM
        cte_timeline_daily AS td
    LEFT JOIN
        datalake_velo.delinquency_timeline AS t
            ON td.id_delinquency = t.id_delinquency
            AND td.dt_updated = COALESCE(t.dt_paid, t.dt_updated)
    LEFT JOIN
        datalake_velo.propose AS p
            ON t.id_propose = p.id_propose
    LEFT JOIN
        datalake_velo.propose_person AS pp
            ON p.id_primary_person = pp.id_person
),
-- major type and aging are calculed per person, not per propose
cte_type_aging AS (
    SELECT
        name,
        document,
        MAX(mob_delinquency) AS mob,
        array_distinct(array_agg(type_description)) AS type_description_array,
        CASE
            WHEN MAX(dt_ended_propose) IS NOT NULL THEN "RECISAO"
            WHEN array_contains(array_agg(type_description), 'TERMINATION') THEN 'RECISAO'
            WHEN array_contains(array_agg(type_description), 'GUARANTEE') THEN 'GARANTIA'
            WHEN array_contains(array_agg(type_description), 'SIGNATURE') THEN 'ASSINATURA'
            ELSE 'CHECK'
        END AS major_type,
        `date`
    FROM
        timeline
    GROUP BY 1,2,6
    ORDER BY 6,1
),
timeline_final AS (
    SELECT
        t.name,
        t.document,
        t.id_propose,
        ta.mob,
        ta.type_description_array,
        ta.major_type,
        SUM(t.delinquency_amount) AS total_delinquency_amount,
        SUM(t.original_value) AS total_original_value,
        SUM(t.amount_paid) AS total_amount_paid,
        SUM(t.amount_paid_added_fixed) AS amount_paid_added,
        SUM(t.open_amount) AS total_open_amount,
        array_agg(t.is_finished) As is_finished_array,
        MAX(t.is_legacy_propose) AS is_legacy_propose,
        MAX(t.is_currently_active) AS is_currently_active,
        MAX(t.dt_ended_propose) AS dt_ended_propose,
        t.`date` AS dt_base,
        array_agg(t.dt_paid) AS dt_paid_array
    FROM
        timeline AS t
    LEFT JOIN
        cte_type_aging AS ta
        ON ta.document = t.document
        AND t.`date` = ta.`date`
    GROUP BY 1,2,3,4,5,6,16
)
SELECT
    t.name,
    t.document,
    t.id_propose,
    t.mob,
    t.type_description_array,
    t.major_type,
    t.total_delinquency_amount,
    t.total_original_value,
    t.total_amount_paid,
    t.amount_paid_added,
    t.total_open_amount,
    t.is_finished_array,
    t.is_legacy_propose,
    t.is_currently_active,
    IF(e.cpf_cnpj IS NOT NULL, TRUE, FALSE) AS has_month_eviction,
    t.dt_ended_propose,
    t.dt_base,
    t.dt_paid_array
FROM
    timeline_final AS t
LEFT JOIN
    datalake_gsheets_clean.quintocred_process_evictions AS e
        ON REGEXP_REPLACE(e.cpf_cnpj, '[^0-9]', '') = t.document
        AND e.dt_distribution >= t.dt_base
        AND (
            e.dt_finalized <= date_trunc('MONTH', t.dt_base)
            OR e.dt_finalized IS NULL
            )
        AND e.is_archived IS FALSE
ORDER BY 17,1
