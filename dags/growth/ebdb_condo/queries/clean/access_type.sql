SELECT
    id,
    authorization_id AS id_authorization,
    imovel_id AS id_house,
    occupant_id AS id_occupant,
    restriction_id AS id_restriction,
    type_id AS id_type,
    additionalinfo AS additional_info,
    description,
    lockeraddress AS locker_address,
    password,    
    CAST(optedkeyswithagent AS BOOLEAN) AS has_opted_keys_with_agent,
    CAST(vacanton AS DATE) AS dt_vacated,
    CAST(criadoem AS TIMESTAMP) AS ts_created,
    CAST(atualizadoem AS TIMESTAMP) AS ts_updated
FROM 
    datalake_ebdb_raw.AccessType