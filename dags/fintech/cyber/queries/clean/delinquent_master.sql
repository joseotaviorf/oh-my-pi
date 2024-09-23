SELECT
    DMSSNUM AS id_client,
    DMACCT AS id_contract,
    DMPROD AS id_product,
    DMAGENCY AS id_agency,
    DMWKFLAG AS id_user,
    CASE
        WHEN DMACCTG = "1" THEN "QuintoAndar"
        WHEN DMACCTG = "2" THEN "QuintoCred"
        ELSE DMACCTG
    END AS contract_group,
    DMSEQNO AS sequence_number,
    CASE
        WHEN DMSTATUS = "R" THEN "Liberada"
        WHEN DMSTATUS = "S" THEN "Satisfeita"
        WHEN DMSTATUS = "W" THEN "Prejuízo"
        WHEN NULLIF(DMSTATUS, "") IS NULL THEN "Conta ativa"
        ELSE DMSTATUS
    END AS contract_status,
    CASE
        WHEN NULLIF(DMPPFLAG,'') IS NULL THEN "Sem promessa de pagamento"
        WHEN DMPPFLAG = "P" THEN "Pendente"
        WHEN DMPPFLAG = "K" THEN "Cumprida"
        WHEN DMPPFLAG = "B" THEN "Quebrada"
        ELSE DMPPFLAG
    END AS flag_promise_payment,
    CASE
        WHEN DMLAFLG IS NULL THEN "Não está em agência e não tem juízo"
        WHEN DMLAFLG = "JR" THEN "Não está em agência e tem requisição de juízo"
        WHEN DMLAFLG = "J" THEN "Não está em agência e tem juízo ativo"
        WHEN DMLAFLG = "JT" THEN "Não está em agência e tem juízo terminado"
        WHEN DMLAFLG = "FA" THEN "Está em agência e não tem juízo"
        WHEN DMLAFLG = "FR" THEN "Está em agência e tem requisição de juízo"
        WHEN DMLAFLG = "FJ" THEN "Está em agência e tem juízo ativo"
        WHEN DMLAFLG = "FT" THEN "Está em agência e tem juízo terminado"
        ELSE DMLAFLG
    END AS flag_account_in_agency_or_court,
    DMPTSCOR AS punctuation,
    DMBRANCH AS branch,
    DMOFFICR AS manager,
    CASE
        WHEN LOWER(DMRELFLG) = "c" THEN "Codevedor únicamente"
        WHEN LOWER(DMRELFLG) = "r" THEN "Relação únicamente"
        WHEN LOWER(DMRELFLG) = "b" THEN "Codevedor e relação"
        ELSE DMRELFLG
    END AS debtor_type,
    DMADL1 AS additional_account_1,
    DMADL2 AS additional_account_2,
    DMSPDESC AS special_description,
    DMSCHDAY AS scheduled_letter_day,
    DMPMTTOT AS total_records_payments,
    DMNUMPLC AS times_account_assigned_agency,
    DMENTRY AS manager_last_payment_promisse,
    DMSALCD AS greeting_code,
    DMNAME AS debtor_name,
    DMPRVNAM AS previous_name,
    DMNAME2 As debtor_name_complement,
    DMPRVNM2 AS previous_complement_name,
    DMADDR1 AS residential_address,
    DMADDR2 AS additional_residential_address,
    DMADDR3 AS neighborhood_residential_address,
    DMPRVAD1 AS previous_address_1,
    DMPRVAD2 AS previous_address_2,
    DMBADDR1 AS business_address,
    DMBADDR2 AS additional_business_address,
    DMBADDR3 AS neighborhood_business_address,
    DMCITY AS city,
    DMSTATE AS state,
    DMZIP AS zip_code,
    DMEMAIL AS email,
    DMPHONE AS residencial_phone,
    DMCPHONE AS cellphone,
    DMPEXT AS main_phone_extension,
    DMCPEXT AS phone_extension,
    DMACODE AS main_area_code,
    DMCACODE AS phone_area,
    DMBNAME AS company_name_work,
    DMBCITY AS city_business_address,
    DMBSTATE AS state_business_address,
    DMBZIP AS zip_code_business_address,
    DMBPHONE AS business_phone,
    DMBPEXT AS phone_extension_work,
    DMAGTYPE AS agreement_type,
    CASE
        WHEN DMAGSTATUS = "A" THEN "Autorizado"
        WHEN DMAGSTATUS = "P" THEN "Pendente"
        WHEN DMAGSTATUS = "C" THEN "Cancelado"
        WHEN DMAGSTATUS = "F" THEN "Finalizado"
        ELSE DMAGSTATUS
    END AS agreement_status,
    CASE
        WHEN DMAGPPSTATUS = "C" THEN "Cumprida"
        WHEN DMAGPPSTATUS = "B" THEN "Quebrada"
        WHEN DMAGPPSTATUS = "P" THEN "Pendente"
        WHEN DMAGPPSTATUS = "S" THEN "Programada"
        ELSE DMAGPPSTATUS
    END AS last_payment_promisse_status,
    DMPRVCTY AS previous_city,
    DMPRVSTA AS previous_state,
    DMPRVZIP AS previous_zip_code,
    DMSUBSET AS contract_subset,
    DMPRVINT AS previous_interest,
    DMCOMPANY AS company,
    DMPRI AS current_priority,
    DMSUPV AS supervisor,
    DMSUPCOM AS reason_last_supervisor_request,
    DMSCODE AS status_supervisor_code,
    CASE
        WHEN DMID = "PE" THEN "Pagamento espontâneo"
        WHEN DMID = "PC" THEN "Pagamento Acordo"
        WHEN DMID = "PP" THEN "Promessa Pagamento"
        WHEN DMID = "ES" THEN "Estorno"
        ELSE DMID
    END AS payment_type,
    DMREVCOD AS review_code,
    DMREASSG AS reassignin_queues,
    DMLASTAC AS last_action,
    DMLASTRC AS last_result,
    DMLASTLC AS last_letter_code,
    DMP1 AS permanent_comment_1,
    DMP2 AS permanent_comment_2,
    DMP3 AS permanent_comment_3,
    DMNUM30 AS times_account_was_30_days_late,
    DMNUM60 AS times_account_was_60_days_late,
    DMNUM90 AS times_account_was_90_days_late,
    DMNUM120 AS times_account_was_120_days_late,
    DMNUM150 AS times_account_was_150_days_late,
    DMNUM180 AS times_account_was_180_days_late,
    DMASSAGCY AS agency_automatically_assigned,
    DMPRVAGN AS previous_agency,
    DMPRVAGN1 AS previous_agency_1,
    DMPRVAGN2 AS previous_agency_2,
    DMPRVAGN3 AS previous_agency_3,
    DMPRVAGN4 AS previous_agency_4,
    DMPRVAGN5 AS previous_agency_5,
    CASE
        WHEN UPPER(DMAGNREJ) = "REJA" THEN "Inativa"
        WHEN UPPER(DMAGNREJ) = "REJB" THEN "Repetida"
        WHEN UPPER(DMAGNREJ) = "REJC" THEN "Agencia repetida em outra conta de arrastro"
        WHEN UPPER(DMAGNREJ) = "REJD" THEN "Agencia ultrapassou o limite de contas permitidas"
        WHEN UPPER(DMAGNREJ) = "REJT" THEN "Valor virtual que identifica as agencias temporais"
        WHEN NULLIF(DMAGNREJ,'') IS NULL THEN "Não se recusa a agencia"
        ELSE DMAGNREJ
    END AS status_agency_declined,
    DMQUE AS segmentation_queue,
    DMQUE2 AS commission_queue,
    DMQUE3 AS agreement_queue,
    DMQUE4 AS dialer_queue,
    DMQUE5 AS eviction_queue,
    DMQUE6 AS credit_denial_queue,
    DMPREVQ AS previous_segmentation_queue,
    DMPREVQ2 AS previous_commission_queue,
    DMPREVQ3 AS previous_agreement_queue,
    DMPREVQ4 AS previous_dialer_queue,
    DMPREVQ5 AS previous_eviction_queue,
    DMPREVQ6 AS previous_credit_denial_queue,
    DMLABEL5 AS eviction_label,
    DMLABEL1 AS label_1,
    DMLABEL2 AS label_2,
    DMLABEL3 AS campaign_label,
    DMLABEL4 AS label_4,
    DMLABEL6 AS label_6,
    DMACAC1 AS most_important_action_class_1,
    DMACAC2 AS most_important_action_class_2,
    DMACAC3 AS most_important_action_class_3,
    DMACAC1_2 AS history_2_most_important_action_class_1,
    DMACAC2_2 AS history_2_most_important_action_class_2,
    DMACAC3_2 AS history_2_most_important_action_class_3,
    DMACAC1_3 AS history_3_most_important_action_class_1,
    DMACAC2_3 AS history_3_most_important_action_class_2,
    DMACAC3_3 AS history_3_most_important_action_class_3,
    DMACAC1_4 AS history_4_most_important_action_class_1,
    DMACAC2_4 AS history_4_most_important_action_class_2,
    DMACAC3_4 AS history_4_most_important_action_class_3,
    DMACAC1_5 AS history_5_most_important_action_class_1,
    DMACAC2_5 AS history_5_most_important_action_class_2,
    DMACAC3_5 AS history_5_most_important_action_class_3,
    DMACRC1 AS most_important_result_class_1,
    DMACRC2 AS most_important_result_class_2,
    DMACRC3 AS most_important_result_class_3,
    DMACRC1_2 AS history_2_most_important_result_class_1,
    DMACRC2_2 AS history_2_most_important_result_class_2,
    DMACRC3_2 AS history_2_most_important_result_class_3,
    DMACRC1_3 AS history_3_most_important_result_class_1,
    DMACRC2_3 AS history_3_most_important_result_class_2,
    DMACRC3_3 AS history_3_most_important_result_class_3,
    DMACRC1_4 AS history_4_most_important_result_class_1,
    DMACRC2_4 AS history_4_most_important_result_class_2,
    DMACRC3_4 AS history_4_most_important_result_class_3,
    DMACRC1_5 AS history_5_most_important_result_class_1,
    DMACRC2_5 AS history_5_most_important_result_class_2,
    DMACRC3_5 AS history_5_most_important_result_class_3,
    DMACLC1 AS most_important_letter_class_1,
    DMACLC2 AS most_important_letter_class_2,
    DMACLC3 AS most_important_letter_class_3,
    DMACLC1_2 AS history_2_most_important_letter_class_1,
    DMACLC2_2 AS history_2_most_important_letter_class_2,
    DMACLC3_2 AS history_2_most_important_letter_class_3,
    DMACLC1_3 AS history_3_most_important_letter_class_1,
    DMACLC2_3 AS history_3_most_important_letter_class_2,
    DMACLC3_3 AS history_3_most_important_letter_class_3,
    DMACLC1_4 AS history_4_most_important_letter_class_1,
    DMACLC2_4 AS history_4_most_important_letter_class_2,
    DMACLC3_4 AS history_4_most_important_letter_class_3,
    DMACLC1_5 AS history_5_most_important_letter_class_1,
    DMACLC2_5 AS history_5_most_important_letter_class_2,
    DMACLC3_5 AS history_5_most_important_letter_class_3,
    DMACSC1 AS score_most_important_activity_class_1,
    DMACSC2 AS score_most_important_activity_class_2,
    DMACSC3 AS score_most_important_activity_class_3,
    DMACSC1_2 AS history_2_most_important_ativity_score_class_1,
    DMACSC2_2 AS history_2_most_important_ativity_score_class_2,
    DMACSC3_2 AS history_2_most_important_ativity_score_class_3,
    DMACSC1_3 AS history_3_most_important_ativity_score_class_1,
    DMACSC2_3 AS history_3_most_important_ativity_score_class_2,
    DMACSC3_3 AS history_3_most_important_ativity_score_class_3,
    DMACSC1_4 AS history_4_most_important_ativity_score_class_1,
    DMACSC2_4 AS history_4_most_important_ativity_score_class_2,
    DMACSC3_4 AS history_4_most_important_ativity_score_class_3,
    DMACSC1_5 AS history_5_most_important_ativity_score_class_1,
    DMACSC2_5 AS history_5_most_important_ativity_score_class_2,
    DMACSC3_5 AS history_5_most_important_ativity_score_class_3,
    DMAGNUMBK AS broken_promisses,
    DMAGPCT AS percentage_paid_agreement,
    DMDAYS AS delay_contamined_days,
    DMCHID AS proof,
    DMSAMPLE AS sample,
    DMBACODE AS work_area,
    DMPPKEPT AS total_promises_kept,
    DMPPBROK AS number_broken_promises,
    DMPRVAMT AS amount_prior_agency,
    DMPRVAMT1 AS amount_prior_agency_1,
    DMPRVAMT2 AS amount_prior_agency_2,
    DMPRVAMT3 AS amount_prior_agency_3,
    DMPRVAMT4 AS amount_prior_agency_4,
    DMPRVAMT5 AS amount_prior_agency_5,
    DMPPAMT AS payment_promisse_amount,
    DMAGNAMT AS current_agency_amount,
    DMPAYAMT AS last_amount_paid,
    DMLTRAMT AS last_letter_amount,
    DMAGAMT AS negotiated_amount,
    DMACUMINT AS accumulated_interest_amount,
    DMPRVAINT AS accumulated_amount,
    DMAMTDLQ AS overdue_amount,
    DMCURBAL AS debt_amount,
    DMPAYOFF AS current_total_overdue,
    DMNXTPOF AS next_due_balance_amount,
    DMOPNAMT AS total_package_amount,
    DMCRLIMT AS credit_limit,
    DMHOSTUP AS ts_last_update,
    DMAGCHGDT AS ts_status_updated,
    DMDLQDT AS ts_due_oldest_invoice,
    DMAGINIPAYDT AS ts_first_payment_agreement,
    DMAGLSTPAYDT AS ts_last_payment_agreement,
    DMLCLUPD AS ts_last_update_manager,
    DMCLASSDT AS ts_manager_assignment,
    DMPAYDT AS ts_last_payment,
    DMNXTCON AS ts_next_contact,
    DMPPMADE AS ts_promise,
    DMPPDUE AS ts_due_promisse_payment,
    DMOPNDT AS ts_credit_opening,
    DMAGNREF AS ts_reference_current_agency,
    DMLSTCON AS ts_last_contact_account,
    DMPOFTIL AS ts_next_due_balance,
    DMLTRDT AS ts_last_letter_request,
    DMCCSDT AS ts_account_registered,
    DMINACCT AS ts_last_account_inactive,
    DMREACT AS ts_last_account_reactivation,
    DMLSTACT AS ts_last_activity,
    DMHISTDT As ts_last_activity_history,
    DMPRVREF AS ts_assignment_previous_agency,
    DMPRVREF1 AS ts_assignment_previous_agency_1,
    DMPRVREF2 AS ts_assignment_previous_agency_2,
    DMPRVREF3 AS ts_assignment_previous_agency_3,
    DMPRVREF4 AS ts_assignment_previous_agency_4,
    DMPRVREF5 AS ts_assignment_previous_agency_5,
    DMASSAGDT AS ts_automatic_assignment,
    DMQCHGDT AS ts_last_update_segmentation_queue,
    DMQCHGDT2 AS ts_last_update_commission_queue,
    DMQCHGDT3 AS ts_last_update_agreement_queue,
    DMQCHGDT4 AS ts_last_update_dialer_queue,
    DMQCHGDT5 AS ts_last_update_eviction_queue,
    DMQCHGDT6 AS ts_last_update_credit_denial_queue,
    DMACDT1 AS ts_most_important_activity_class_1,
    DMACDT2 AS ts_most_important_activity_class_2,
    DMACDT3 AS ts_most_important_activity_class_3,
    DMACDT1_2 AS ts_history_2_most_important_activity_class_1,
    DMACDT2_2 AS ts_history_2_most_important_activity_class_2,
    DMACDT3_2 AS ts_history_2_most_important_activity_class_3,
    DMACDT1_3 AS ts_history_3_most_important_activity_class_1,
    DMACDT2_3 AS ts_history_3_most_important_activity_class_2,
    DMACDT3_3 AS ts_history_3_most_important_activity_class_3,
    DMACDT1_4 AS ts_history_4_most_important_activity_class_1,
    DMACDT2_4 AS ts_history_4_most_important_activity_class_2,
    DMACDT3_4 AS ts_history_4_most_important_activity_class_3,
    DMACDT1_5 AS ts_history_5_most_important_activity_class_1,
    DMACDT2_5 AS ts_history_5_most_important_activity_class_2,
    DMACDT3_5 AS ts_history_5_most_important_activity_class_3,
    DMPRVIDT AS ts_previous_interest_calculation,
    DMINTDT AS ts_last_interest_calculation,
    NOW() AS ts_load
FROM datalake_cyber_raw.delqmst
