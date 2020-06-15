select
    id,
    external_id as id_external,
    invoice_id as id_invoice,
    acquirer_auth_code,
    acquirer_fee_amount,
    advance_fee_amount,
    brand_name,
    charged_amount,
    installments,
    status,
    timestamp(created_at) as ts_created,
    acquirer_transaction_id as id_acquirer_transaction,
    acquirer_nsu
from datalake_retsuko_raw.credit_card_payment
