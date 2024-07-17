select
    id,
    vistoria_id as id_inspection,
    roomId as id_room,
    refId as id_ref,
    temFoto as has_photo,
    nome as name,
    tipo as type,
    posicao as position,
    nomeFoto as photo_name,
    roomName as room_name,
    acabamento as finishing,
    funcionamento as operation,
    comentario as comment,
    comentarioInquilino as tenant_comment,
    comentarioProprietario as owner_comment,
    criadoEm as ts_created,
    atualizadoEm as ts_updated
from
    datalake_ebdb_test_raw.itemvistoria
