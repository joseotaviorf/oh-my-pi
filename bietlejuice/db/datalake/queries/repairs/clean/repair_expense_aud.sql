SELECT 
    id, 
    expense_group_id AS id_expense_group,
    rev, 
    revend AS rev_end, 
    CAST(revtype AS INTEGER) AS rev_type, 
    name AS repair_name, 
    description AS repair_description,
    instant_approval,
    responsible_after_grace,
    responsible_before_grace,
    expense_group_id_mod AS mod_id_expense_group, 
    name_mod AS mod_repair_name,
    description_mod AS mod_repair_description, 
    instant_approval_mod AS mod_instant_approval, 
    responsible_after_grace_mod AS mod_responsible_after_grace, 
    responsible_before_grace_mod AS mod_responsible_before_grace 
FROM 
    datalake_repairs_raw.repair_expense_aud 