SELECT
    id,
    chargeId AS id_charge,
    nsu,
    referenceNumber AS reference_number,
    protocolNumber AS protocol_number,
    acquirerStoreCode AS acquirer_store_code,
    saleSummaryNumber AS sale_summary_number,
    reasonCode AS reason_code,
    metadata,
    authorizationCode AS authorization_code,
    sheetNumber AS sheet_number,
    terminalCode AS terminal_code,
    cardFirstSixDigits AS card_first_six_digits,
    cardLastFourDigits AS card_last_four_digits,
    message,
    CAST(transactionDate AS TIMESTAMP) AS ts_transaction,
    CAST(requestDate AS TIMESTAMP) AS ts_request,
    CAST(returnDate AS TIMESTAMP) AS ts_return,
    chargebackAmount AS chargeback_amount,
    transactionAmount AS transaction_amount
FROM
    datalake_wall_street_raw.chargebacknotification;
