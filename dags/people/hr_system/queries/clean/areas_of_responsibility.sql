SELECT
    ResponsibilityId AS id_responsibility,
    PersonId AS id_person,
    AssignmentId AS id_assignment,
    TemplateId AS id_template,
    LegalEntityId AS id_legal_entity,
    DepartmentId AS id_department,
    PersonNumber AS person_number,
    AssignmentNumber AS assignment_number,
    UPPER(AssignmentName) AS assignment_name,
    ResponsibilityName AS responsibility_name,
    ResponsibilityType AS responsibility_type,
    DisplayName AS display_name,
    TemplateCode AS template_code,
    TemplateName AS template_name,
    ActiveStatus AS active_status,
    Usage,
    BOOLEAN(WorkContactsFlag) AS is_work_contacts,
    TO_DATE (StartDate, 'yyyy-MM-dd') AS dt_started,
    TO_DATE (EndDate, 'yyyy-MM-dd') AS dt_ended,
    ts_load
FROM
    datalake_hr_system_raw.areas_of_responsibility
