SELECT
    PAACCT AS id_contract,
    PAIDPARC AS id_invoice,
    PAIDBOL AS id_boleto,
    PABICODIGO AS id_entry,
    PANUMDOBOL AS boleto_number,
    PANOSSNUM AS our_number,
    PANOSNUMBOL AS our_number_boleto,
    CASE
        WHEN PATIPO = "P" THEN "Invoice"
        WHEN PATIPO = "B" THEN "Entry"
        ELSE PATIPO
    END invoice_or_entry,
    PAACCTG AS contract_group,
    CASE
        WHEN PAACCTG = "1" THEN "QuintoAndar"
        WHEN PAACCTG = "2" THEN "QuintoCred"
        ELSE PAACCTG
    END AS creditor,
    CASE
        WHEN PASTATUS = 1 THEN "Ativa (em aberto)"
        WHEN PASTATUS = 2 THEN "Paga"
        WHEN PASTATUS = 3 THEN "Cancelada"
        WHEN PASTATUS = 4 THEN "Pausa"
        WHEN PASTATUS = 5 THEN "Previamente negociada"
        WHEN PASTATUS = 6 THEN "Em negociação"
        ELSE PASTATUS
    END AS invoice_status,
    PASTATFA AS retsuko_status,
    PATPDIV AS purpose,
    PAINDMOTPA AS pause_reason,
    PATPCONTA AS account_type,
    PAAMENVFA AS accrual_year_month,
    IF(PAINDNEG = "S", TRUE, FALSE) AS is_negative_bureaus,
    IF(PAINDPRIFA = "S", TRUE, FALSE) AS is_tenant_first_invoice,
    IF(PAPREVNEG = "S", TRUE, FALSE) AS has_previously_negotiated,
    PACODBANBOL AS bank_code,
    PADIGBANBOL AS bank_digit,
    PANOMBANBOL AS bank_name,
    PACODAGBOL AS company_agency_account_digit,
    CONCAT(PALINDIG1, '.', PALINDIG2, ' ', PALINDIG3, '.', PALINDIG4, ' ', PALINDIG5, '.', PALINDIG6, ' ', PALINDIG7, ' ', PALINDIG8) AS charge_barcode,
    CONCAT(IFNULL(PALININSTBOL1, ""), IFNULL(PALININSTBOL2, ""), IFNULL(PALININSTBOL3, ""), IFNULL(PALININSTBOL4, ""), IFNULL(PALININSTBOL5, ""), IFNULL(PALININSTBOL6, ""), IFNULL(PALININSTBOL7, ""), IFNULL(PALININSTBOL8, "")) AS charge_instructions,
    PALOCPAGBOL AS payment_location_boleto,
    CASE
        WHEN PATPPECEBOL = "F" THEN "Fisica"
        WHEN PATPPECEBOL = "J" THEN "Juridica"
        ELSE PATPPECEBOL
    END AS type_transferor,
    CASE
        WHEN PATPDOPCBOL = "1" THEN "CNPJ"
        WHEN PATPDOPCBOL = "2" THEN "CPF"
        ELSE PATPDOPCBOL
    END AS type_transferor_document,
    PADOCPECEBOL AS transferor_document,
    PANOCEBOL AS transferor_name,
    CASE
        WHEN PATPPESABOL = "F" THEN "Fisica"
        WHEN PATPPESABOL = "J" THEN "Juridica"
        ELSE PATPPESABOL
    END AS drawer_type,
     CASE
        WHEN PATPDPSABOL = "1" THEN "CNPJ"
        WHEN PATPDPSABOL = "2" THEN "CPF"
        ELSE PATPDPSABOL
    END AS drawer_document_type,
    PADOPESABOL AS drawer_document,
    PANOSABOL AS drawer_name,
    PASEREARBOL AS bill_record_sequence_2,
    PASEQREARBOL AS bill_record_sequence_3,
    PABIFLGEXCLLOG As is_bill_item_deleted,
    IFNULL(PAVLRORI, 0) AS due_amount,
    IFNULL(PAVLPRINC, 0) AS main_amount,
    IFNULL(PAVLJUR, 0) AS interest_amount,
    IFNULL(PAVLMUL, 0) AS fine_amount,
    IFNULL(PACUSTAS, 0) AS eviction_costs_amount,
    IFNULL(PAHONORARIOS, 0) AS eviction_honorarium_amount,
    PABITITULO AS entry_title,
    PABIDESC AS entry_description,
    PABIVALOR AS entry_amount,
    PAVLRBOL AS bill_amount,
    PAVLDESCBOL AS bill_discount_amount,
    PAVLDEDUBOL AS bill_deductions_amount,
    PAVLRMOMUBOL AS bill_fees_amount,
    PAVLACRBOL AS bill_additions_amount,
    PAVLRTOBOL AS bill_total_amount,
    PADTCRIPA AS ts_creation,
    PADTVENORI AS ts_due,
    PADTVENC AS ts_installment_due,
    PADTVENCBOL AS ts_due_boleto,
    PABIDTVENC AS ts_entry_due,
    PADTENVFA AS ts_sent,
    PADTLIMPA AS ts_limit_pause,
    PADTDOCBOL AS ts_issue_boleto,
    PABIDTINSERT AS ts_entry_insert,
    PABIDTUPDATE AS ts_entry_update,
    PADTINSERT AS ts_insert,
    PADTUPDATE AS ts_update,
    PABIDTEXCLUSAO AS ts_bill_item_deleted,
    PADTUPDREG AS ts_record_updated,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_cyber_raw.tb_parcela
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY ROW_NUMBER() OVER(PARTITION BY PAACCT, PAACCTG, PAIDPARC, PABICODIGO, PATIPO ORDER BY MAKE_DATE(year,month,day) DESC) = 1
