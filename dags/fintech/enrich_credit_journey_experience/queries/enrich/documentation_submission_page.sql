WITH union_documentation_submission_events AS (
SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_list_viewed_events
WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_personal_viewed_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_selfie_clicked_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_selfieok_submit_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_document_photo_clicked_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_personal_submit_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_basicinfo_viewed_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_basicinfo_submit_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_income_clicked_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_income_submit_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_address_viewed_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_address_submit_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_session,
  id_amplitude,
  id_user,
  GET_JSON_OBJECT(event_properties, "$.proposalId") AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_type AS event_name,
  "Documentation submission page" AS event_source,
  event_properties,
  GET_JSON_OBJECT(event_properties, "$.isDocumentationComplete") AS is_documentation_complete,
  GET_JSON_OBJECT(event_properties, "$.isRetenant") AS is_retenant,
  GET_JSON_OBJECT(event_properties, "$.hasResendInfo") AS is_resend,
  GET_JSON_OBJECT(event_properties, "$.isFastPass") AS is_fast_pass,
  GET_JSON_OBJECT(event_properties, "$.iqQuantity") AS number_of_proponents,
  ts_event,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.170698_doc_tenants_submit_complete_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  CAST(id_session AS bigint) AS id_session,
  CAST(id_amplitude AS bigint) AS id_amplitude,
  CAST(id_user AS bigint) AS id_user,
  CAST(id_proposal AS bigint) AS id_proposal,
  city,
  region,
  country,
  device_family,
  version_name,
  event_name,
  event_source,
  CAST(number_of_proponents AS int) AS number_of_proponents,
  CAST(is_documentation_complete AS boolean) AS is_documentation_complete,
  CAST(is_retenant AS boolean) AS is_retenant,
  CAST(is_resend AS boolean) AS is_resend,
  CAST(is_fast_pass AS boolean) AS is_fast_pass,
  ts_event,
  year,
  month,
  day
FROM
  union_documentation_submission_events
