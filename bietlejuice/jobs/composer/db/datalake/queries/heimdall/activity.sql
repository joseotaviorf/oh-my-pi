select
    -- format: {"$oid": "5b9ffb4da939ee6a2c873276"}
    regexp_extract(_id, '\\"(\\w+)\\"', 1) as id,
    cast(houseid as bigint) as id_house,
    cast(externalcontractid as bigint) as id_external_contract,
    _class as class,
    status,
    type,
    transitionlist as transition_list,
    metadata,
    -- obs: all values of createdAt and updatedAt are equal to Zero. As the database is a Mongo, we don't know the format. 
    timestamp(createdAt) as ts_created,
    timestamp(updatedAt) as ts_updated
from datalake_heimdall_raw.activity