import datetime
import petl
from jobs.base.base_etl import BaseETL, EnumDb
from jobs.wrappers.GoogleDrive.google_drive_api import GoogleDriveApi


def get_list_descredenciados():
    AGENT_ID_COLUMN = 2
    DATE_COLUMN = 1
    agentes = BaseETL.from_db_query(
        EnumDb.QuintoAndar_ebdb,
        query=
        """
            select
              u.dadosAgente_id,
              u.email
            from
              Usuario u
            inner JOIN
              DadosAgente da
              on u.dadosAgente_id = da.id
            order by 1
        """
    )
    name = 'Corretores - Lista atualizada'
    file_name, file_path_destination = GoogleDriveApi().download_file(
        file_name=name,
        file_path_destination='/tmp',
        file_name_destination=name + '.xlsx'
    )
    d = {}
    if file_name and file_path_destination:
        file_name = '{}/{}'.format(file_path_destination, file_name)
        desc = petl.fromxlsx(filename=file_name, sheet='Descredenciados').cut('Emails','Data do Descredenciamento')
        table_desc = petl.join(left=desc, right=agentes, lkey='Emails', rkey='email')[1:]

        for line in table_desc:
            d[line[AGENT_ID_COLUMN]] = line[DATE_COLUMN].date()

    return d


def get_agent_schedule():
    descredenciados = get_list_descredenciados()

    db = BaseETL.get_connection(db_enum=EnumDb.QuintoAndar_ebdb)
    cursor = db.cursor()
    cursor.execute("""
        SELECT  agente_id,
                atualizadoEm,
                diaDaSemana,
                horarios_disponivel08as09,
                horarios_disponivel09as10,
                horarios_disponivel10as11,
                horarios_disponivel11as12,
                horarios_disponivel12as13,
                horarios_disponivel13as14,
                horarios_disponivel14as15,
                horarios_disponivel15as16,
                horarios_disponivel16as17,
                horarios_disponivel17as18,
                horarios_disponivel18as19,
                horarios_disponivel19as20
        FROM HorarioSemanalAgente_AUD
        ORDER BY agente_id, diaDaSemana, atualizadoEm ASC
        """)
    horario_semanal = []
    for row in cursor.fetchall():
        horario_semanal.append([])
        for element in row:
            horario_semanal[-1].append(element)
    horarios = {}
    current_agent = -1
    current_weekday = -1
    last_update = 0
    current_date = 0
    for index in range(len(horario_semanal)):
        row = horario_semanal[index]

        if current_date == 0:
            current_weekday = row[2]
            current_agent = row[0]
            last_update = row[1]
            current_date = row[1] + datetime.timedelta(
                days=current_weekday + 7 * (last_update.weekday() + 1 > current_weekday) - (last_update.weekday() + 1))
            continue

        if current_weekday != row[2] or current_agent != row[0]:

            limit = 0
            if current_agent in descredenciados:
                limit = descredenciados[current_agent]
            else:
                limit = datetime.datetime.today().date()

            while current_date.date() < limit:
                last = horario_semanal[index - 1]
                horarios[(current_agent, current_date.date())] = last[3:]
                current_date += datetime.timedelta(days=7)

        else:

            limit = 0
            if current_agent in descredenciados:
                limit = descredenciados[current_agent]
            else:
                limit = row[1].date()

            while current_date.date() < limit:
                last = horario_semanal[index - 1]
                horarios[(current_agent, current_date.date())] = last[3:]
                current_date += datetime.timedelta(days=7)

        current_agent = row[0]
        current_weekday = row[2]
        last_update = row[1]
        current_date = last_update + datetime.timedelta(
            days=current_weekday + 7 * (last_update.weekday() + 1 > current_weekday) - (last_update.weekday() + 1))

    cursor.execute("""
        SELECT  agente_id,
                data,
                folga,
                disponivel8as9,
                disponivel9as10,
                disponivel10as11,
                disponivel11as12,
                disponivel12as13,
                disponivel13as14,
                disponivel14as15,
                disponivel15as16,
                disponivel16as17,
                disponivel17as18,
                disponivel18as19,
                disponivel19as20
        FROM HorarioEspecificoAgente
        """)

    for row in cursor.fetchall():
        key = (row[0], row[1])
        if key in horarios:
            if row[2]:
                horarios[key] = [0] * 12
            else:
                horarios[key] = row[3:]

    db.close()

    list_horarios = []
    for key, value in horarios.iteritems():
        temp = [key[0], key[1]]
        temp.extend(value)
        list_horarios.append(temp)

    table = petl.pushheader(list_horarios, [
        'agente_id',
        'data',
        'disponivel08as09',
        'disponivel09as10',
        'disponivel10as11',
        'disponivel11as12',
        'disponivel12as13',
        'disponivel13as14',
        'disponivel14as15',
        'disponivel15as16',
        'disponivel16as17',
        'disponivel17as18',
        'disponivel18as19',
        'disponivel19as20'
    ])
    return table


BaseETL.bulk_insert(
    table=get_agent_schedule(),
    table_name='agent_schedule',
    db_enum=EnumDb.BI_ODS,
    append=False,
    commit=True
)

