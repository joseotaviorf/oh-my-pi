select
   id,
   feature_id as id_feature,
   template_id as id_template,
   resource_id as id_resource,
   parent_id as id_parent,
   priority_order,
   required as is_required,
   visible_options
from datalake_insider_raw.template_feature