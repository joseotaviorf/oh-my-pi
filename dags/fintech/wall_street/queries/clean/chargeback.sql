SELECT
    id,
    chargeId AS id_charge,
    transactionId AS id_trasaction,
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
    adjustmentAmount AS adjustment_amount,
    totalInstallments As total_installments,
    installment,
    sentToBankDate AS dt_sent_to_bank,
    acquirerReferenceDate AS dt_acquirer_reference_date,
    adjustmentEntryDate AS dt_adjustment_entry
FROM
    datalake_wall_street_raw.chargeback
