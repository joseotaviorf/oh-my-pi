select
    _id as id,
    houseid as id_house,
    externalcontractid as id_external_contract,
    _class as class,
    status,
    type,
    transitionlist as transition_list,
    metadata,
    updatedat as ts_updated,
    createdat as ts_created
from datalake_heimdall_raw.activity