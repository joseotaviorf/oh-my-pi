SELECT 
    id, 
    parent_id AS id_parent,
    rev,
    revend AS rev_end, 
    revtype AS rev_type,
    name AS repair_group_name, 
    description AS repair_group_description,
    parent_id_mod AS mod_id_parent, 
    name_mod AS mod_repair_group_name,
    description_mod AS mod_repair_group_description
FROM 
    datalake_repairs_raw.repair_expense_group_aud