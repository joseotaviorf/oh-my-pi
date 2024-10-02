select
    id,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    category,
    description,
    positivo as is_positive,
    active as is_active
from
    datalake_ebdb_test_raw.feedbacktag
