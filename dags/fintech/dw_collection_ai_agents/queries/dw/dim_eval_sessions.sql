SELECT
    id_session,
    MAX(CASE WHEN s.name = 'MatthewSessionEvaluation' THEN 'Old Tag Format' ELSE 'New Tag Format' END) AS status_tag_format,
    MAX(CASE WHEN s.name = 'MatthewSessionEvaluation' THEN string_value ELSE NULL END) AS old_tag_value,
    MAX(CASE WHEN s.name = 'MatthewTextTagAuthenticationRequested' THEN s.value ELSE 0 END) AS eval_auth_requested,
    MAX(CASE WHEN s.name = 'MatthewTextTagAuthenticationCompleted' THEN s.value ELSE 0 END) AS eval_auth_completed,
    MAX(CASE WHEN s.name = 'MatthewTextTagDebtPresented' THEN s.value ELSE 0 END) AS eval_debt_presented,
    MAX(CASE WHEN s.name = 'MatthewTextTagNegotiationOffered' THEN s.value ELSE 0 END) AS eval_negotiation_offered,
    MAX(CASE WHEN s.name = 'MatthewTextTagUserRequestedAlternative' THEN s.value ELSE 0 END) AS eval_user_requested_alternative,
    MAX(CASE WHEN s.name = 'MatthewTextTagNegotiationClosed' THEN s.value ELSE 0 END) AS eval_negotiation_closed,
    MAX(CASE WHEN s.name = 'MatthewTextTagBotEncounteredError' THEN s.value ELSE 0 END) AS eval_bot_encountered_error,
    MAX(CASE WHEN s.name = 'MatthewTextTagNoContractFound' THEN s.value ELSE 0 END) AS eval_no_contract_found,
    MAX(CASE WHEN s.name = 'MatthewTextTagNoMatthewInteraction' THEN s.value ELSE 0 END) AS eval_no_matthew_interaction,
    MAX(CASE WHEN s.name = 'MatthewTextTagSessionEscalatedToHumanSupport' THEN s.value ELSE 0 END) AS eval_escalated_to_human,
    MAX(CASE WHEN s.name = 'MatthewTextTagUserDisagreed' THEN s.value ELSE 0 END) AS eval_user_disagreed,
    MAX(CASE WHEN s.name = 'MatthewTextTagAuthenticationRequested' AND s.value = 1 THEN 'Authentication Requested' ELSE NULL END) AS status_authentication_requested,
    MAX(CASE WHEN s.name = 'MatthewTextTagAuthenticationCompleted' AND s.value = 1 THEN 'Authentication Completed' ELSE NULL END) AS status_authentication_completed,
    MAX(CASE WHEN s.name = 'MatthewTextTagDebtPresented' AND s.value = 1 THEN 'Debt Presented' ELSE NULL END) AS status_debt_presented,
    MAX(CASE WHEN s.name = 'MatthewTextTagNegotiationOffered' AND s.value = 1 THEN 'Negotiation Offered' ELSE NULL END) AS status_negotiation_offered,
    MAX(CASE WHEN s.name = 'MatthewTextTagUserRequestedAlternative' AND s.value = 1 THEN 'User Requested Alternative' ELSE NULL END) AS status_user_requested_alternative,
    MAX(CASE WHEN s.name = 'MatthewTextTagNegotiationClosed' AND s.value = 1 THEN 'Negotiation Closed' ELSE NULL END) AS status_negotiation_closed,
    MAX(CASE WHEN s.name = 'MatthewTextTagBotEncounteredError' AND s.value = 1 THEN 'Bot Encountered Error' ELSE NULL END) AS status_bot_encountered_error,
    MAX(CASE WHEN s.name = 'MatthewTextTagNoContractFound' AND s.value = 1 THEN 'No Contract Found' ELSE NULL END) AS status_no_contract_found,
    MAX(CASE WHEN s.name = 'MatthewTextTagNoMatthewInteraction' AND s.value = 1 THEN 'No Matthew Interaction' ELSE NULL END) AS status_no_matthew_interaction,
    MAX(CASE WHEN s.name = 'MatthewTextTagSessionEscalatedToHumanSupport' AND s.value = 1 THEN 'Session Escalated To Human Support' ELSE NULL END) AS status_escalated_to_human,
    MAX(CASE WHEN s.name = 'MatthewTextTagUserDisagreed' AND s.value = 1 THEN 'User Disagreed' ELSE NULL END) AS status_user_disagreed
FROM
    datalake_langfuse_clean.scores s
WHERE 1=1
    AND (s.name = 'MatthewSessionEvaluation' OR s.name LIKE '%MatthewTextTag%')
    AND id_session IS NOT NULL
GROUP BY
    id_session
