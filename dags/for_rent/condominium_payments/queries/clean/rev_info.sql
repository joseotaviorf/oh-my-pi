SELECT
    rev,
    user_id AS id_user,
    personified_main_user_id AS id_personified_main_user,
    person_uuid AS uuid_person,
    FROM_UNIXTIME(revtstmp/1000, 'yyyy-MM-dd HH:mm:ss') AS ts_revision
FROM
    datalake_condominium_payments_raw.revinfo
