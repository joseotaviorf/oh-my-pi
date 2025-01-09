WITH timeline AS (
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
        t.amount_paid,
        t.amount_paid_added,
        t.open_amount,
        t.open_amount_first_day_of_month,
        t.is_finished,
        t.is_legacy_agreement,
        t.is_legacy_propose,
        t.is_currently_active,
        t.dt_due,
        t.dt_ended_propose,
        t.dt_paid,
        t.dt_base,
        dt_aging,
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
min_dates AS (
    SELECT
        document,
        MIN(CASE WHEN type_description = 'GUARANTEE' THEN dt_aging END) AS min_dt_guarantee,
        MIN(CASE WHEN type_description IN ('RENEWAL', 'SIGNATURE') THEN dt_aging END) AS min_dt_signature,
        MIN(CASE WHEN type_description = 'RESCISAO' THEN dt_aging END) AS min_dt_termination
    FROM
        datalake_collections_quintocred.mob_delinquency_timeline
    GROUP BY 1
),
min_propose_date AS (
    SELECT
        id_propose,
        MIN(dt_aging) AS min_dt_propose
    FROM
        datalake_collections_quintocred.mob_delinquency_timeline
    GROUP BY 1
),
document_major_type AS (
    SELECT
        document,
        `date`,
        array_distinct(array_agg(major_type)) AS major_type_array,
        array_distinct(array_agg(monthly_major_type)) AS monthly_major_type_array,
        CASE
            WHEN array_contains(array_agg(major_type), 'GARANTIA') THEN 'GARANTIA'
            WHEN array_contains(array_agg(major_type), 'RESCISAO') THEN 'RESCISAO'
            ELSE any_value(major_type)
        END AS major_type,
        CASE
            WHEN array_contains(array_agg(monthly_major_type), 'GARANTIA') THEN 'GARANTIA'
            WHEN array_contains(array_agg(monthly_major_type), 'RESCISAO') THEN 'RESCISAO'
            ELSE any_value(monthly_major_type)
        END AS monthly_major_type
    FROM
        datalake_collections_quintocred.major_type_distribution
    GROUP BY 1,2
),
timeline_final AS (
    SELECT
        t.name,
        t.document,
        t.id_propose,
        MAX(t.mob_delinquency) AS mob,
        ta.type_description_array AS type_description_array,
        mt.major_type,
        mt.monthly_major_type,
        SUM(t.delinquency_amount) AS total_delinquency_amount,
        SUM(t.original_value) AS total_original_value,
        SUM(t.amount_paid) AS total_amount_paid,
        SUM(t.amount_paid_added) AS amount_paid_added,
        SUM(t.open_amount) AS total_open_amount,
        array_agg(t.is_finished) As is_finished_array,
        MAX(t.is_legacy_propose) AS is_legacy_propose,
        MAX(t.is_currently_active) AS is_currently_active,
        MAX(t.dt_ended_propose) AS dt_ended_propose,
        dt_base,
        t.dt_aging,
        array_agg(t.dt_paid) AS dt_paid_array,
        CASE
            WHEN ta.major_type = 'RESCISAO' AND md.min_dt_termination IS NULL THEN md.min_dt_guarantee
            WHEN ta.major_type = 'RESCISAO' THEN md.min_dt_termination
            WHEN ta.major_type = 'GARANTIA' THEN md.min_dt_guarantee
            WHEN ta.major_type = 'ASSINATURA' THEN md.min_dt_signature
        END AS dt_min_major_type,
        MIN(mpd.min_dt_propose) AS dt_min_propose
    FROM
        timeline AS t
    LEFT JOIN
        datalake_collections_quintocred.major_type_distribution AS ta
        ON ta.document = t.document
        AND ta.id_propose = t.id_propose
        AND t.`date` = ta.`date`
    LEFT JOIN
        document_major_type AS mt
        ON mt.document = t.document
        AND t.`date` = mt.`date`
    LEFT JOIN
        min_dates AS md
        ON t.document = md.document
    LEFT JOIN
        min_propose_date AS mpd
        ON t.id_propose = mpd.id_propose
    GROUP BY 1,2,3,5,6,7,17,18,21
),
evictions_day AS (
    SELECT
        d.`date`,
        DATE_TRUNC('MONTH', d.`date`) AS month,
        REGEXP_REPLACE(e.cpf_cnpj, '[^0-9]', '') AS document
    FROM
        datalake_quintoandar.aux_date AS d
    LEFT JOIN
        datalake_gsheets_clean.quintocred_process_evictions AS e
          ON d.`date` >= e.dt_register
          AND (
              DATE_TRUNC('MONTH', d.`date`) <= e.dt_finalized
              OR e.dt_finalized IS NULL
              )
WHERE
    d.`date` < CURRENT_DATE()
    AND e.is_archived IS FALSE
)
SELECT
    t.name,
    t.document,
    t.id_propose,
    t.mob,
    t.type_description_array,
    t.major_type,
    t.monthly_major_type,
    t.total_delinquency_amount,
    t.total_original_value,
    t.total_amount_paid,
    t.amount_paid_added,
    t.total_open_amount,
    DATE_DIFF(DATE_TRUNC('MONTH', t.dt_base), t.dt_min_major_type) AS lead_time_major_type,
    DATE_DIFF(DATE_TRUNC('MONTH', t.dt_base), t.dt_min_propose) AS lead_time_propose,
    t.is_finished_array,
    t.is_legacy_propose,
    t.is_currently_active,
    IF(e.cpf_cnpj IS NOT NULL, TRUE, FALSE) AS has_month_eviction,
    IF(ed.document IS NOT NULL, TRUE, FALSE) AS has_active_day_eviction,
    IF(FIRST_VALUE(em.document) IS NOT NULL, TRUE, FALSE) AS has_active_month_eviction,
    t.dt_ended_propose,
    t.dt_base,
    t.dt_min_major_type,
    t.dt_min_propose,
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
LEFT JOIN
    evictions_day ed
        ON t.document = ed.document
        AND ed.`date` = t.dt_base
LEFT JOIN
    evictions_day em
        ON t.document = em.document
        AND em.month = DATE_TRUNC('MONTH', t.dt_base)
GROUP BY ALL
ORDER BY 18,1
