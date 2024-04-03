SELECT
    cod_parc AS id_installment,
    cod_tit AS id_contract,
    cod_imp AS id_import,
    devolvido_parc AS is_returned,
    parcelado_parc AS is_payment_in_installments,
    quitado_parc AS is_paid,
    numero_parc AS installment_number,
    vr_parc AS amount,
    dt_entrada_parc AS ts_entry_installment,
    vcto_parc AS ts_due,
    dt_bord_parc AS ts_inclusion,
    NOW() AS ts_load
FROM datalake_webhelp_raw.parcelas
