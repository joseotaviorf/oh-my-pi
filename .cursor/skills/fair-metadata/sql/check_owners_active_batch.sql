-- Verify multiple metadata owners are ACTIVE employees (F2-01 owner_not_active_employee).
-- Run via trino/SKILL.md (fair-metadata invokes automatically).
-- Replace the IN list with lowercase-trimmed corporate emails from metadata owner: fields.

SELECT
    work_email,
    assignment_status_type
FROM datalake_people_public.org_chart
WHERE LOWER(TRIM(work_email)) IN (
    'owner1@quintoandar.com.br',
    'owner2@quintoandar.com.br'
)
  AND assignment_status_type = 'ACTIVE'
