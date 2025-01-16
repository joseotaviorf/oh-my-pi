SELECT
    id,
    REV AS rev,
    reVTYPE as rev_type,
    imovel_id AS id_house,
    imovel_MOD as mod_house,
    status,
    status_MOD as mod_status,
    reason,
    reason_MOD as mod_reason
from datalake_ebdb_test_raw.housevisitstatus_aud
