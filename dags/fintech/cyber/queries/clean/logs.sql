SELECT
    ACACCT AS id_contract,
    ACCIDNAM AS id_user,
    ACACCTG AS contract_group,
    CASE
        WHEN ACACCTG = "1" THEN "QuintoAndar"
        WHEN ACACCTG = "2" THEN "QuintoCred"
        ELSE ACACCTG
    END AS creditor,
    ACARCOD AS region_code,
    ACACCODE AS action,
    ACRCCODE AS result,
    ACLCCODE AS complement,
    ACSEQNUM AS sequence_number,
    ACCOMM AS comment,
    ACPHONE AS phone_number,
    ACEXT AS phone_extension,
    ACLAT AS latitude,
    ACLNG AS longitude,
    ACACTDTE AS ts_activity,
    ACENTDTE AS ts_load_cyber,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_cyber_raw.actfil
WHERE ACACTDTE BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
