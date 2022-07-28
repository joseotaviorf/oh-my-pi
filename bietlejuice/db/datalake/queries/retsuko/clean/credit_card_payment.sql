SELECT
    id,
    external_id AS id_external,
    invoice_id AS id_invoice,
    acquirer_transaction_id AS id_acquirer_transaction,
    acquirer_auth_code,
    acquirer_nsu,
    brand_name,
    status,
    installments,
    acquirer_fee_amount,
    advance_fee_amount,
    charged_amount,
    is_recurrent,
    created_at AS ts_created
FROM
    datalake_retsuko_raw.credit_card_payment
