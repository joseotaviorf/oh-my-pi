select
  "id",
  comentario as "comment",
  nomeFoto as photo_name,
  roomId as id_room,
  roomName as room_name,
  vistoria_id as id_inspection,
  nome as name,
  refId as id_reference,
  tipo as "type",
  temFoto as has_photo,
  atualizadoEm as ts_updated,
  criadoEm as ts_created,
  posicao as position,
  acabamento as finishing,
  funcionamento as operation,
  comentarioInquilino as tenant_comment,
  comentarioProprietario as owner_comment
from ItemVistoria
;