SELECT
    id,
    chargeId AS id_charge,
    transactionId AS id_transaction,
    externalId AS id_external,
    processId AS id_process,
    acquirer,
    acquirerCode AS acquirer_code,
    nsu,
    cardCode AS card_code,
    cardFirstSixDigits AS card_first_six_digits,
    cardLastFourDigits AS card_last_four_digits,
    authorizationCode AS authorization_code,
    companyDocument AS company_document,
    metadata,
    CAST(sentToBankDate AS TIMESTAMP) AS ts_sent_to_bank,
    CAST(acquirerReferenceDate AS TIMESTAMP) AS ts_acquirer_reference,
    CAST(adjustmentEntryDate AS TIMESTAMP) AS ts_adjustment_entry,
    adjustmentAmount AS adjustment_amount,
    totalInstallments AS total_installments,
    installment
FROM
    datalake_wall_street_raw.chargeback
