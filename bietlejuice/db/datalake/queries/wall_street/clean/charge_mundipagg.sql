select
    id,
    acquireMessage as acquire_message,
    amount,
    cardId as id_card,
    timestamp(createdAt) as ts_created,
    currency,
    customerId as id_customer,
    gatewayId as id_gateway,
    timestamp(paidAt) as ts_paid,
    paymentMethod as payment_method,
    status,
    timestamp(updatedAt) as ts_updated,
    acquireReturnCode as acquire_return_code,
    acquireAuthCode as acquire_auth_code,
    acquireNsu as acquire_nsu,
    acquireTid as id_acquire_transaction
from datalake_wall_street_raw.chargemundipagg
