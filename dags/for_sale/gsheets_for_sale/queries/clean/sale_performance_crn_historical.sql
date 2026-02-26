SELECT
    id_offer,
    id_house,
    crn_partner,
    crn_agent,    
    due_lead_time_bookkeeping_reason,
    due_lead_time_cri_reason,
    observations,
    status,
    has_house_chattel_mortgage,
    is_continue_with_crn_partner,
    lt_first_contact,
    lt_bookkeeping,
    lt_cri_request,
    lt_cri,
    lt_total,
    dt_sale_agreement_signed,
    dt_dd_accepted,
    dt_sheets_inclusion,
    dt_crn_first_contact,
    dt_bookkeeping_done,
    dt_cri_request,
    dt_cri_done    
FROM
    datalake_gsheets_raw.sale_performance_crn_historical



