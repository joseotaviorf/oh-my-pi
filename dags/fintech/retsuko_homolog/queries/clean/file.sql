select
    id,
    name,
    path,
    timestamp(created_at) as ts_created,
    type
from
    datalake_retsuko_homolog_raw.file
