SELECT
    contract_id AS id_contract,
    process_number AS id_process,
    imovel_number as id_house,
    ticket_number as id_ticket_number,
    sentence_number as id_sentence_number,
    lawsuit_against_number as id_lawsuit_against,

    alert_str AS alert_message,
    resp AS responsible,
    process_status,
    action_type as action_type_name,
    deal_status,
    contract_status,
    off_status,
    status_cs,
    general_comments,
    judge_district,
    comments_lawsuit_against,
    ending_reason,
    informed_distribution,
    process_comunication_status,
    city,
    validator_execution,

    CASE 
        WHEN is_cav = "Sim" THEN TRUE
        WHEN is_cav = "Não" THEN FALSE
    END AS is_cav,
    CASE 
        WHEN is_fraud = "Sim" THEN TRUE
        WHEN is_fraud = "Não" THEN FALSE
    END AS is_fraud,
    
    CASE 
        WHEN abandonment_bool = "Sim" THEN TRUE
        WHEN abandonment_bool = "Não" THEN FALSE
    END AS is_abandonment,

    CASE 
        WHEN iq_comunicated_bool = "Sim" THEN TRUE
        WHEN iq_comunicated_bool = "Não" THEN FALSE
    END AS is_iq_comunicated,

    CASE 
        WHEN reoccurent_bool = "Sim" THEN TRUE
        WHEN reoccurent_bool = "Não" THEN FALSE
    END AS is_reoccurent,

    CASE 
        WHEN office_comunicated_bool = "Sim" THEN TRUE
        WHEN office_comunicated_bool = "Não" THEN FALSE
    END AS is_office_comunicated,


    TO_DATE(insertion_date, 'dd/MM/yyyy') as dt_insertion,
    TO_DATE(sentence_date, 'dd/MM/yyyy') as dt_sentence,
    TO_DATE(final_sentence_date, 'dd/MM/yyyy') as dt_final_sentence,
    TO_DATE(distribution_date, 'dd/MM/yyyy') as dt_distribution,
    TO_DATE(deal_begin_date, 'dd/MM/yyyy') as dt_deal_begin,
    TO_DATE(deal_end_date, 'dd/MM/yyyy') as dt_deal_end,
    TO_DATE(deal_paid_dt, 'dd/MM/yyyy') as dt_deal_paid,
    TO_DATE(no_deal_paid_dt, 'dd/MM/yyyy') as dt_no_deal_paid,
    TO_DATE(finalizing_dt, 'dd/MM/yyyy') as dt_finalizing,
    TO_DATE(termination_dt, 'dd/MM/yyyy') as dt_contract_termination,
    TO_DATE(verification_dt, 'dd/MM/yyyy') as dt_verification,
    TO_DATE(distribution_cs_dt, 'dd/MM/yyyy') as dt_distribution_cs,
    TO_DATE(sentence_cs_dt, 'dd/MM/yyyy') as dt_sentence_cs,
    TO_DATE(eviction_order_dt, 'dd/MM/yyyy') as dt_eviction_order,
    TO_DATE(change_ending_dt, 'dd/MM/yyyy') as dt_change_ending,
    TO_DATE(change_ended_dt, 'dd/MM/yyyy') as dt_change_ended,
    TO_DATE(massive_dt, 'dd/MM/yyyy') as dt_registry_date,
    TO_DATE(second_massive_dt, 'dd/MM/yyyy') as dt_process_closing,
    TO_DATE(validity, 'dd/MM/yyyy') as dt_validity

FROM
    datalake_gsheets_raw.evictions_processes_forrent