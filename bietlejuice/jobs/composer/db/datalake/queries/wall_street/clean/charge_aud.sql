select
    id, 
    REV as rev, 
    REVTYPE as rev_type,
    REVEND as rev_end,
    acquire, 
    acquireId as id_acquire,  
    chargeStatus as charge_status,
    externalId as id_external,
    lastUpdate as ts_updated,
    acquireChargeStatus as acquire_charge_status,
    acquireAuthCode as acquire_auth_code
from datalake_wall_street_raw.charge_aud