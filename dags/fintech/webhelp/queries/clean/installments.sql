SELECT
    cod_parc AS id_installment,
    cod_tit AS id_title,
    cod_imp AS id_import,
    devolvido_parc AS is_returned,
    parcelado_parc AS is_payment_in_installments,
    quitado_parc AS is_paid,
    numero_parc AS installment_number,
    vr_parc AS due_amount,
    dt_entrada_parc AS ts_entry_installment,
    vcto_parc AS ts_due,
    dt_bord_parc AS ts_inclusion,
    NOW() AS ts_load
FROM datalake_webhelp_raw.parcelas
QUALIFY ROW_NUMBER() OVER(PARTITION BY cod_parc ORDER BY subfolder DESC) = 1
