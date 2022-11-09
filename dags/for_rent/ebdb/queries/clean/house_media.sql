select
    id,
    house_id as id_house,
    type,
    url,
    created_on as ts_created,
    updated_on as ts_updated
from
    datalake_ebdb_raw.housemedia