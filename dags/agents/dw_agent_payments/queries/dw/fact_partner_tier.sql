SELECT
    pt.id_partner_tier AS sk_partner_tier,
    pt.id_new_partner_tier AS sk_new_partner_tier,
    pt.id_tier AS sk_tier,
    person.sk_person AS sk_person,
    overwritten_by.sk_person AS sk_overwritten_by,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    pt.incentive_system,
    pt.tier_name,
    pt.overwritten_reason,
    pt.is_valid,
    pt.is_overwritten,
    pt.is_overwritten_by_ops,
    pt.dt_validity_started,
    pt.dt_validity_ended,
    pt.ts_overwritten,
    pt.ts_created,
    pt.ts_updated,
    NOW() AS ts_load,
    pt.year,
    pt.month,
    pt.day
FROM
    datalake_big_agent.partner_tier AS pt
LEFT JOIN
    datalake_person.person_sks AS person
        ON pt.uuid_person = person.uuid_person
LEFT JOIN
    datalake_person.person_sks AS overwritten_by
        ON pt.uuid_overwritten_by = overwritten_by.uuid_person
LEFT JOIN
    core_brokers.brokers AS cb
        ON pt.uuid_company = cb.uuid_company
WHERE
    DATE(pt.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
