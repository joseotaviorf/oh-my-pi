SELECT
    ACACCT AS id_contract,
    ACCIDNAM AS id_user,
    CASE
        WHEN ACACCTG = "1" THEN "QuintoAndar"
        WHEN ACACCTG = "2" THEN "QuintoCred"
        ELSE ACACCTG
    END AS contract_group,
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
    NOW() AS ts_load
FROM datalake_cyber_raw.actfil
