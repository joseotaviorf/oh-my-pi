
WITH delinquency_end AS (
    SELECT DISTINCT
        id_delinquency,
        dt_updated
    FROM
        datalake_velo.delinquency_timeline
    WHERE
        is_finished
),
timeline_base AS (
    SELECT
        t.*,
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
        MAX(t.dt_updated) AS dt_updated
    FROM
        datalake_quintoandar.aux_date AS d
    LEFT JOIN
        timeline_base AS t
            ON IF(t.is_finished, d.`date` >= t.dt_updated AND d.`date` <= LAST_DAY(t.dt_updated), d.`date` >= t.dt_updated AND d.`date` < t.dt_delinquency_last_register)
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
        INT(months_between(td.month_start, t.dt_created)) AS mob_delinquency,
        t.*,
        IF(td.`date` <> t.dt_updated, 0.00, t.amount_paid_added) AS amount_paid_added_fixed
    FROM
        cte_timeline_daily AS td
    LEFT JOIN
        datalake_velo.delinquency_timeline AS t
            ON td.id_delinquency = t.id_delinquency
            AND td.dt_updated = t.dt_updated
    LEFT JOIN
        datalake_velo.propose AS p
            ON t.id_propose = p.id_propose
    LEFT JOIN
        datalake_velo.propose_person AS pp
            ON p.id_primary_person = pp.id_person
)

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
    SUM(delinquency_amount) AS total_delinquency_amount,
    SUM(original_value) AS total_original_value,
    SUM(amount_paid) AS total_amount_paid,
    SUM(amount_paid_added_fixed) AS amount_paid_added,
    SUM(open_amount) AS total_open_amount,
    array_agg(is_finished) As is_finished_array,
    MAX(dt_ended_propose) AS dt_ended_propose,
    `date` AS dt_base,
    array_agg(dt_paid) AS dt_paid_array
FROM
    timeline
GROUP BY 1,2,13
ORDER BY 13, 1
