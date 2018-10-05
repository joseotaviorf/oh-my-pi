select
  ST_AsText(pr.poligono) as polygon,
  mr.id as region_id,
  mr.nome as region_name
from PoligonoRegiao pr
join MapRegiao mr
  on pr.regiao_id = mr.id