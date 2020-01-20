select
   id,
   review_id as id_review,
   feature_id as id_feature,
   resource_id as id_resource,
   rating_selected,
   comment
from datalake_insider_raw.review_feature