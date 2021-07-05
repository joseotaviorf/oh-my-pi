SELECT
    GET_JSON_OBJECT(REPLACE(_id, '$', ''), '$.oid') AS id,
    CAST(externalcontractid AS BIGINT) AS id_external_contract,
    CAST(houseid AS BIGINT) AS id_house,
    _class AS class,
    status AS status,
    type AS type,
    transitionlist AS transition_list,
    metadata,
    -- obs: all values of createdAt and updatedAt are equal to Zero. As the database is a Mongo, we don't know the format. 
    CAST(FROM_UNIXTIME(createdAt/10000) AS TIMESTAMP) AS ts_created,
    CAST(FROM_UNIXTIME(updatedAt/1000) AS TIMESTAMP) AS ts_updated
FROM 
    datalake_heimdall_raw.activity