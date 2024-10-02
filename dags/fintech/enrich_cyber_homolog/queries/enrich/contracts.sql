SELECT
    c.id_contract,
    c.id_contract_external,
    c.id_client,
    c.id_contract_property,
    c.id_oldest_negative_invoice,
    c.id_last_negative_installment,
    dm.status_agency_declined,
    c.delay_contamined_days,
    c.contract_group,
    c.is_boletagem,
    c.collection_classification,
    c.has_paused_collection,
    c.reason_pause,
    c.contract_version,
    c.contract_guarantee,
    c.contract_status,
    c.eviction_step,
    c.reason_eviction,
    c.eviction_law_firm,
    c.open_invoices,
    c.collection_flow,
    c.has_restrictive_evic_occurrence,
    dm.agreement_type,
    dm.agreement_status,
    dm.last_payment_promisse_status,
    dm.flag_promise_payment,
    dm.flag_account_in_agency_or_court,
    dm.last_action,
    c.has_serasa_credit_denial,
    dm.segmentation_queue,
    qdts.queue_name AS segementation_queue_description,
    dm.previous_segmentation_queue,
    qdtps.queue_name AS previous_segementation_queue_description,
    dm.agreement_queue,
    qdta.queue_name AS agreement_queue_description,
    dm.previous_agreement_queue,
    qdtpa.queue_name AS previous_agreement_queue_description,
    dm.digital_channel_queue,
    qdtcd.queue_name AS digital_channel_queue_description,
    dm.previous_digital_channel_queue,
    qdtpcd.queue_name AS previous_digital_channel_queue_description,
    dm.eviction_queue,
    qdte.queue_name AS eviction_queue_description,
    dm.previous_eviction_queue,
    qdtpe.queue_name AS previous_eviction_queue_description,
    dm.credit_denial_queue,
    qdtn.queue_name AS credit_denial_queue_description,
    dm.previous_credit_denial_queue,
    qdtpn.queue_name AS previous_credit_denial_queue_description,
    dm.olos_dialer_label,
    qdto.queue_name AS olos_dialer_label_description,
    dm.campaign_label,
    qdtc.queue_name AS campaign_label_description,
    dm.pre_legal_label,
    qdtpj.queue_name AS pre_legal_label_description,
    dm.id_agency AS agency,
    dm.agency_automatically_assigned,
    dm.times_account_assigned_agency,
    dm.previous_agency,
    dm.current_agency_amount,
    dm.amount_prior_agency,
    dm.overdue_amount,
    dm.debt_amount,
    dm.total_package_amount,
    c.oldest_negative_invoice_amount,
    c.contract_rental_amount,
    c.contract_condominium_amount,
    c.contract_iptu_amount,
    c.ts_start_guarantee,
    c.ts_contract_start,
    c.ts_contract_end,
    dm.ts_account_registered,
    dm.ts_last_update,
    c.ts_due_oldest_negative_invoice,
    dm.ts_due_oldest_invoice,
    dm.ts_first_payment_agreement,
    dm.ts_last_payment_agreement,
    dm.ts_last_payment,
    dm.ts_next_contact,
    dm.ts_reference_current_agency,
    dm.ts_last_account_inactive,
    dm.ts_last_account_reactivation,
    dm.ts_last_activity,
    dm.ts_assignment_previous_agency,
    dm.ts_last_update_segmentation_queue,
    dm.ts_last_update_agreement_queue,
    dm.ts_last_update_eviction_queue,
    dm.ts_last_update_credit_denial_queue,
    NOW() AS ts_load
FROM datalake_cyber_clean.contracts AS c
LEFT JOIN datalake_cyber_clean.delinquent_master AS dm
 ON c.id_contract = dm.id_contract
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdts
    ON dm.segmentation_queue = qdts.queue AND qdts.queue_type = 'Segmentação'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdtps
    ON dm.previous_segmentation_queue = qdtps.queue AND qdtps.queue_type = 'Segmentação'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdta
    ON dm.agreement_queue = qdta.queue AND qdta.queue_type = 'Acordo'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdtpa
    ON dm.previous_agreement_queue = qdtpa.queue AND qdtpa.queue_type = 'Acordo'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdtcd
    ON dm.digital_channel_queue = qdtcd.queue AND qdtcd.queue_type = 'Canais Digitais'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdtpcd
    ON dm.previous_digital_channel_queue = qdtpcd.queue AND qdtpcd.queue_type = 'Canais Digitais'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdte
    ON dm.eviction_queue = qdte.queue AND qdte.queue_type = 'Eviction'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdtpe
    ON dm.previous_eviction_queue = qdtpe.queue AND qdtpe.queue_type = 'Eviction'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdtn
    ON dm.credit_denial_queue = qdtn.queue AND qdtn.queue_type = 'Negativação'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdtpn
    ON dm.previous_credit_denial_queue = qdtpn.queue AND qdtpn.queue_type = 'Negativação'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdto
    ON dm.olos_dialer_label = qdto.queue AND qdto.queue_type = 'Discador Olos'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdtc
    ON dm.campaign_label = qdtc.queue AND qdtc.queue_type = 'Campaign'
LEFT JOIN datalake_cyber_homolog.queue_decision_tree AS qdtpj
    ON dm.pre_legal_label = qdtpj.queue AND qdtpj.queue_type = 'Pré Jurídico'
