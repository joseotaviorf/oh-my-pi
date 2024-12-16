SELECT
  avatarUrls AS avatar_urls,
  entityId AS id_entity,
  expand,
  id,
  isPrivate AS is_private,
  key,
  name,
  projectTypeKey AS project_type_key,
  properties,
  self,
  simplified AS is_simplified,
  style,
  uuid
FROM
    datalake_jira_raw.projects
