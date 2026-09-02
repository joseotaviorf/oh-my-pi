SELECT
    Id AS id,
    CreatedById AS id_created_by,
    ParentId AS id_parent,
    Field AS changed_field_name,
    DataType AS data_type_name,
    NewValue AS new_value,
    OldValue AS old_value,
    IsDeleted AS is_deleted,
    CreatedDate AS ts_created,
    CAST(CreatedDate AS DATE) AS dt_updated,
    YEAR(CreatedDate) AS year,
    MONTH(CreatedDate) AS month,
    DAY(CreatedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.empresa_portal__history
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
