SELECT
   id,
   feature_id AS id_feature,
   template_id AS id_template,
   resource_id AS id_resource,
   parent_id AS id_parent,
   priority_order,
   visible_options,
   required AS is_required
FROM
   datalake_insider_test_raw.template_feature
