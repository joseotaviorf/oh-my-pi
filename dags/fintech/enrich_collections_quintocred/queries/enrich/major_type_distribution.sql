WITH timeline AS (
-- major type and aging are calculed per person, not per propose
    SELECT
        t.name,
        t.document,
        t.id_propose,
        MAX(t.mob_delinquency) AS mob,
        array_distinct(array_agg(t.type_description)) AS type_description_array,
        CASE
            WHEN array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'TERMINATION') THEN 'TERMINATION'
            WHEN MAX(t.dt_ended_propose) < t.`date` AND array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'GUARANTEE') THEN "TERMINATION"
            WHEN array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'GUARANTEE') THEN 'GUARANTEE'
            WHEN array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'SIGNATURE') THEN 'SIGNATURE'
            WHEN array_contains(array_agg(if(t.is_active_timeline is TRUE AND t.is_finished IS FALSE,t.type_description,null)), 'RENEWAL') THEN 'SIGNATURE'
            ELSE NULL
        END AS major_type,
        CASE
            WHEN array_contains(array_agg(t.type_description), 'TERMINATION') THEN 'TERMINATION'
            WHEN MAX(t.dt_ended_propose) < t.`date` AND array_contains(array_agg(t.type_description), 'GUARANTEE') THEN "TERMINATION"
            WHEN array_contains(array_agg(t.type_description), 'GUARANTEE') THEN 'GUARANTEE'
            WHEN array_contains(array_agg(t.type_description), 'SIGNATURE') THEN 'SIGNATURE'
            WHEN array_contains(array_agg(t.type_description), 'RENEWAL') THEN 'SIGNATURE'
            ELSE 'CHECK'
        END AS monthly_major_type,
        t.`date`
    FROM
        datalake_collections_quintocred.mob_delinquency_timeline t
    GROUP BY 1,2,3,8
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
