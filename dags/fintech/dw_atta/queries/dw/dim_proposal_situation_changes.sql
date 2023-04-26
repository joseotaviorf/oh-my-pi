SELECT
    id_proposal     AS sk_proposal,
    id_partner      AS sk_partner,
    proposal_order,
    proposal_status,
    situation_history,
    next_situation,
    lead_time_situation_in_hour,
    lead_time_situation_in_day,
    lead_time_status_in_day,
    ts_proposal_registration,
    ts_start_situation,
    ts_end_situation,
    NOW()           AS ts_load
FROM datalake_atta.proposal_situation_changes
