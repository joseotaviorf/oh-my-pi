SELECT DISTINCT
    MD5(
      COALESCE(type, 'N/A') ||
      COALESCE(status, 'N/A')  ||
      COALESCE(status_made_by, 'N/A') ||
      COALESCE(status_description, 'N/A') ||
      COALESCE(cancellation_reason, 'N/A') ||
      COALESCE(source, 'N/A')
    ) AS sk_appointment_component,
    type,
    status,
    status_made_by,
    status_description,
    cancellation_reason,
    source
FROM
    datalake_inspections.appointment_inspection
