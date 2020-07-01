select
  avatarUrls as avatar_urls,
  entityId as id_entity,
  expand,
  id,
  isPrivate as is_private,
  key,
  name,
  projectTypeKey as project_type_key,
  properties,
  self,
  simplified as is_simplified,
  style,
  uuid
from datalake_jira_raw.projects
