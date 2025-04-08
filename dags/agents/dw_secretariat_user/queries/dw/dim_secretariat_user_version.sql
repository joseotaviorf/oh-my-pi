SELECT
    (sah.id_secretariat_user * 1000 + sah.`version`) AS sk_secretariat_user_version,
    sah.id_secretariat_user,
    sah.id_supervisor_user,
    sah.id_business_unit,
    sah.allocation,
    sah.segment,
    LAST(sah.allocation) OVER (
        PARTITION BY sah.id_secretariat_user ORDER BY sah.`version`
        ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
    ) AS latest_allocation,
    LAST(sah.segment) OVER (
        PARTITION BY sah.id_secretariat_user ORDER BY sah.`version`
        ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
    ) AS latest_segment,
    sah.profile,
    sah.business_context,
    sah.secretariat_name AS name,
    sah.secretariat_email AS email,
    u.main_phone,
    u.country_code,
    sah.supervisor_name,
    sah.supervisor_email,
    sah.`version`,
    ROW_NUMBER() OVER(PARTITION BY sah.id_secretariat_user ORDER BY sah.`version` DESC) = 1 AS is_last_version,
    sah.ts_allocation_started,
    sah.ts_allocation_ended,
    NOW() AS ts_load
FROM
    datalake_hub_services.secretariat_allocation_history AS sah
JOIN
    datalake_ebdb_user.`user` AS u
        ON sah.id_secretariat_user = u.id
