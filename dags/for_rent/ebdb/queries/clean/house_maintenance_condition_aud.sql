SELECT
    id AS id_house_maintenance_condition,
    REV AS rev,
    REVTYPE AS rev_type,
    maintenanceCondition AS maintenance_condition,
    houseId AS id_house
FROM
    datalake_ebdb_raw.housemaintenancecondition_aud
