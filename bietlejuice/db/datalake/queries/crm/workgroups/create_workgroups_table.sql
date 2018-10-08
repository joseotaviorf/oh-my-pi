select
  cw.id,
  tt.task_type,
  cw.title
from datalake_raw.crm_workgroups cw
cross join unnest(task_types) as tt (task_type)
group by 1, 2, 3
-- grouping necessary for duplicate task types.
-- ex: ["UploadPDFsComAssinatura","FollowUpAssinaturas","FollowUpAssinaturasFinal","FollowUpAssinaturas"]
;