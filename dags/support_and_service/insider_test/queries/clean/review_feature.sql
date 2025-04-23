SELECT
   id,
   review_id AS id_review,
   feature_id AS id_feature,
   resource_id AS id_resource,
   rating_selected,
   comment
FROM
   datalake_insider_test_raw.review_feature
