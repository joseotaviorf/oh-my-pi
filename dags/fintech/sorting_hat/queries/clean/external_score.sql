select
    id,
    cpf,
    source,
    value,
    timestamp(created_at) as ts_created
from datalake_sorting_hat_raw.externalscore