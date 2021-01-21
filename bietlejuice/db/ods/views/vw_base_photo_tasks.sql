--drop view if exists vw_base_photo_tasks;
--create or replace view vw_base_photo_tasks as
SELECT distinct
  COALESCE(h.id, h_direct.id)::INTEGER AS house_id,
  MAX((task_type = 'AgendarJobDeFotografo')::INTEGER)::BOOLEAN AS has_job_photo,
  MAX((task_type = 'FupFoto')::INTEGER)::BOOLEAN AS has_fup_photo
FROM crm.photo_tasks AS pt
LEFT JOIN photo_job AS pj
  ON pt.origin_id = pj.id
LEFT JOIN house AS h
  ON h.id = pj.imovel_id
LEFT JOIN house AS h_direct
  ON h_direct.id = pt.origin_id
WHERE COALESCE(h.id, h_direct.id) IS NOT NULL
GROUP BY 1
