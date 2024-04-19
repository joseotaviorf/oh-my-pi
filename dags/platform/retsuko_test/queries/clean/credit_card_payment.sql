SELECT
    id,
    external_id AS id_external,
    invoice_id AS id_invoice,
    acquirer_transaction_id AS id_acquirer_transaction,
    recurrent_credit_card_id AS id_recurrent_credit_card,
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
    datalake_retsuko_test_raw.credit_card_payment
