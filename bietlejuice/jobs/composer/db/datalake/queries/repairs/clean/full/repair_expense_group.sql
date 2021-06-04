SELECT 
    id, 
    parent_id AS id_parent, 
    name AS repair_group_name, 
    description AS repair_group_description, 
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_repairs_raw.repair_expense_group 
    