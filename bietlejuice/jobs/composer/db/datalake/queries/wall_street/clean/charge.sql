select
    id, 
    acquire, 
    acquireId as id_acquire, 
    amount, 
    chargeStatus as charge_status,
    code,
    customerId as id_customer,
    externalId as id_external,
    lastUpdate as ts_updated,
    store_id as id_store,
    acquireChargeStatus as acquire_charge_status,
    installments, 
    acquireAuthCode as acquire_auth_code,
    acquireNsu as acquire_nsu,
    acquireTid as id_acquire_transaction
from datalake_wall_street_raw.charge