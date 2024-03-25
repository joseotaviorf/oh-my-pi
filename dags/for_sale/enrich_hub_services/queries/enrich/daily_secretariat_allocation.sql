SELECT
    (sah.id_secretariat_user * 1000 + sah.`version`) AS sk_secretariat_user_version,
    sah.id_secretariat_user,
    sah.version,
    ad.`date` AS dt_snapshot
FROM
    datalake_hub_services.secretariat_allocation_history AS sah
JOIN
    datalake_quintoandar.aux_date AS ad
        ON (ad.`date`::TIMESTAMP) BETWEEN sah.ts_allocation_started AND COALESCE(sah.ts_allocation_ended, CURRENT_TIMESTAMP)
WHERE
    ad.`date` BETWEEN '{load_start_date}' AND '{load_end_date}'
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY sah.id_secretariat_user, ad.`date` ORDER BY sah.ts_allocation_started DESC) = 1 