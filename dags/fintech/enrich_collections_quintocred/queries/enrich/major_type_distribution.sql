WITH timeline_base AS (
    SELECT
        t.id_delinquency,
        t.id_propose,
        t.id_status,
        pp.name,
        pp.document,
        CASE
            WHEN is_legacy_agreement THEN INT(months_between(date_trunc('MONTH', t.dt_base), t.dt_due))
            WHEN t.type_description = 'SIGNATURE' AND t.dt_created >= DATE('2024-02-01') THEN INT(months_between(date_trunc('MONTH', t.dt_base), t.dt_due))
            ELSE INT(months_between(date_trunc('MONTH', t.dt_base), t.dt_created))
        END AS mob_delinquency,
        t.type_description,
        t.delinquency_amount,
        t.original_value,
        t.amount_paid_added,
        t.amount_paid_added_month,
        t.amount_paid_added_accrual,
        t.open_amount,
        t.open_amount_deducted,
        t.open_amount_first_day_of_month,
        t.is_finished,
        t.is_legacy_agreement,
        t.is_legacy_propose,
        t.is_currently_active,
        t.is_active_timeline,
        t.dt_due,
        t.dt_ended_propose,
        t.dt_base,
        t.dt_paid,
        t.dt_base AS `date`,
        t.dt_created
    FROM
        datalake_collections_quintocred.delinquency_timeline AS t
    LEFT JOIN
        datalake_velo.propose AS p
            ON t.id_propose = p.id_propose
    LEFT JOIN
        datalake_velo.propose_person AS pp
            ON p.id_primary_person = pp.id_person
),
timeline AS (
-- major type and aging are calculed per person, not per propose
    SELECT
        t.name,
        t.document,
        t.id_propose,
        MAX(t.mob_delinquency) AS mob,
        t.is_finished,
        t.is_active_timeline,
        array_distinct(array_agg(t.type_description)) AS type_description_array,
        CASE
            WHEN array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'TERMINATION') THEN 'TERMINATION'
            WHEN DATE_TRUNC('MONTH', MAX(t.dt_ended_propose)) < DATE_TRUNC('MONTH', t.`date`) AND array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'GUARANTEE') THEN "TERMINATION"
            WHEN array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'GUARANTEE') THEN 'GUARANTEE'
            WHEN array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'SIGNATURE') THEN 'SIGNATURE'
            WHEN array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'RENEWAL') THEN 'SIGNATURE'
            ELSE NULL
        END AS major_type,
        CASE
            WHEN array_contains(array_agg(t.type_description), 'TERMINATION') THEN 'TERMINATION'
            WHEN DATE_TRUNC('MONTH', MAX(t.dt_ended_propose)) < DATE_TRUNC('MONTH', t.`date`) AND array_contains(array_agg(t.type_description), 'GUARANTEE') THEN "TERMINATION"
            WHEN array_contains(array_agg(t.type_description), 'GUARANTEE') THEN 'GUARANTEE'
            WHEN array_contains(array_agg(t.type_description), 'SIGNATURE') THEN 'SIGNATURE'
            WHEN array_contains(array_agg(t.type_description), 'RENEWAL') THEN 'SIGNATURE'
            ELSE 'CHECK'
        END AS monthly_major_type,
        t.`date`
    FROM
        timeline_base t
    GROUP BY 1,2,3,5,6,10
    ORDER BY 7,1
)
SELECT
    name,
    document,
    id_propose,
    mob,
    type_description_array,
    COALESCE(
        major_type,
        LAG(major_type) IGNORE NULLS OVER (
            PARTITION BY name, document, id_propose
            ORDER BY date
        )
    ) AS major_type,
    monthly_major_type,
    `date`
FROM
    timeline
GROUP BY 1,2,3,4,5,7,8, major_type
