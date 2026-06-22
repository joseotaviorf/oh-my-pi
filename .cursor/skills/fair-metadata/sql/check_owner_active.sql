-- Verify metadata owner is an ACTIVE employee (F2-01 owner_not_active_employee).
-- Run via trino/SKILL.md (fair-metadata).
-- Replace :owner_email with the value from metadata ``owner`` (lowercase trim).

SELECT
    work_email,
    assignment_status_type
FROM datalake_people_public.org_chart
WHERE LOWER(TRIM(work_email)) = LOWER(TRIM(:owner_email))
  AND assignment_status_type = 'ACTIVE'
LIMIT 1
