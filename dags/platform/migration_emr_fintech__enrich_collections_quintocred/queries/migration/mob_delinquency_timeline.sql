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
    t.dt_aging,
    t.dt_created
FROM
    datalake_collections_quintocred.delinquency_timeline AS t
LEFT JOIN
    datalake_velo.propose AS p
        ON t.id_propose = p.id_propose
LEFT JOIN
    datalake_velo.propose_person AS pp
        ON p.id_primary_person = pp.id_person
