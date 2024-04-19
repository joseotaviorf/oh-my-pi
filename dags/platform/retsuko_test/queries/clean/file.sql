select
    id,
    name,
    path,
    timestamp(created_at) as ts_created,
    type
from
    datalake_retsuko_test_raw.file