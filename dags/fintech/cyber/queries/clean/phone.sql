SELECT
    PHSSNUM AS id_client,
    PHACCT AS id_contract,
    CASE
        WHEN PHACCTG = "1" THEN "QuintoAndar"
        WHEN PHACCTG = "2" THEN "QuintoCred"
        ELSE PHACCTG
    END AS contract_group,
    CASE
        WHEN PHTYPE = "0" THEN "Outra"
        WHEN PHTYPE = "1" THEN "Casa"
        WHEN PHTYPE = "2" THEN "Trabalho"
        WHEN PHTYPE = "4" THEN "Familiar"
        WHEN PHTYPE = "5" THEN "Celular"
        ELSE PHTYPE
    END AS phone_type,
    PHAREACODE AS area_code,
    PHPHONE AS phone_number,
    PHEXT AS phone_extension,
    IF(PHSTATUS = "A", TRUE, FALSE) AS is_active,
    PHSTCOLLID AS manager_status_update,
    PHSTREASON AS status_reason,
    PHCOLLID AS manager,
    PHRANK AS phone_rank,
    PHRELNUM AS related_number,
    PHRANKORDER AS hierarchical_sequence,
    PHSELFCURE,
    PHRERID,
    PHID,
    PHUPDDT AS ts_hierarchy_calculation,
    PHDATE AS ts_creation,
    PHSTATDT AS ts_status_update
FROM datalake_cyber_raw.phone
