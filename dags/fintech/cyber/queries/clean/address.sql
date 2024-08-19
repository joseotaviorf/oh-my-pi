SELECT
    ADSSNUM AS id_client,
    ADACCT AS id_contract,
    CASE
        WHEN ADACCTG = "1" THEN "QuintoAndar"
        WHEN ADACCTG = "2" THEN "QuintoCred"
        ELSE ADACCTG
    END AS contract_group,
    CASE
        WHEN ADTYPE = "0" THEN "Outra"
        WHEN ADTYPE = "1" THEN "Casa"
        WHEN ADTYPE = "2" THEN "Trabalho"
        WHEN ADTYPE = "3" THEN "Correio Eletrônico"
        WHEN ADTYPE = "4" THEN "Familiar"
        ELSE ADTYPE
    END AS address_type,
    IF(ADLETTERS="Y",TRUE,FALSE) AS is_letter_address,
    ADADDR1 AS address,
    ADADDR2 AS neighborhood,
    ADADDR3 AS complement,
    IF(ADPRI="Y",TRUE,FALSE) AS is_primary_address,
    ADCITY AS city,
    ADSTATE AS state,
    ADZIP AS zip_code,
    IF(ADSTATUS = "A", TRUE, FALSE) AS is_active,
    CASE
        WHEN ADSTREASON = "DU" THEN "Duplicado"
        WHEN ADSTREASON = "ER" THEN "Errado"
        WHEN ADSTREASON = "OU" THEN "Outros"
        WHEN ADSTREASON = "AL" THEN "Alterado"
        ELSE ADSTREASON
    END AS status_reason,
    ADDATE AS ts_creation,
    ADCOLLID AS manager,
    ADSTCOLLID AS manager_update_status,
    ADSTATDT AS ts_status_update,
    ADLNG,
    ADLAT,
    ADSELFCURE,
    ADRERID,
    ADID
FROM datalake_cyber_raw.address
