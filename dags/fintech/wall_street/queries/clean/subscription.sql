select
    id,
    externalid as id_external,
    customerid as id_customer,
    storeid as id_store,
    creditcardid as id_credit_card,
    businessentityid as id_business_entity,
    financeentityid as id_finance_entity,
    code,
    recurrence,
    status,
    currency,
    acquire,
    payername as payer_name,
    payerdocumentnumber as payer_document_number,
    createdat as ts_created,
    canceledat as ts_canceled,
    updatedat as ts_updated,
    startat as dt_start
from 
    datalake_wall_street_raw.subscription