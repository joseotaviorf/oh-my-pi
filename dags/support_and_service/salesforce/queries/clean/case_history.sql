SELECT
    Id AS id_case_history,
    CaseId AS id_case,
    CreatedById AS id_created_by,
    Field AS field_name,
    DataType AS data_type,
    OldValue AS old_value,
    NewValue AS new_value,
    CAST(IsDeleted AS BOOLEAN) AS is_deleted,
    CAST(CreatedDate AS TIMESTAMP) AS ts_created,
    year,
    month,
    day
FROM
    datalake_salesforce_raw.case_history
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
