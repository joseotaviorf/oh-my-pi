import os
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb
from qa_python_utils.default_logger import logger, _logger

from __init__ import ODS_DIR

SCHEMA = 'unit_economics'
QUERIES_DIR = '{}/{}'.format(ODS_DIR, 'unit_economics/views')


def materialize_view(filename):
    dim_name = filename.replace('vw_', '').replace('.sql', '')
    table_name = 'tbl_{}'.format(dim_name)
    print dim_name
    return dim_name
    # print 'drop and create ' + filename
    # print 'insert into ' + table_name


def load_dependent_views(path, parent_folder):
    operator_list = []
    parent_view = 'vw_{}_costs.sql'.format(parent_folder)
    parent_view_exists = False
    for filename in os.listdir(path):
        p = os.path.join(path, filename)
        if os.path.isdir(p) is True:
            folder_name = os.path.basename(p)
            operator_list.append(load_dependent_views(p, '{}_{}'.format(parent_folder, folder_name)))
        else:
            file_name = os.path.basename(p)
            if file_name != parent_view:
                operator_list.append(materialize_view(file_name))
            else:
                parent_view_exists = True
    if parent_view_exists:
        operator_list.append(materialize_view(parent_view))
    return operator_list


def load_fact_unit_economics():
    # create base views
    # liquidity
    liquidity_path = '{}/{}'.format(QUERIES_DIR, 'liquidity')
    operators = load_dependent_views(liquidity_path, 'liquidity')
    for subtree in operators:
        if len(subtree) > 1 and isinstance(subtree, list):
            for dependency in subtree[:-1]:
                print '{} depends on {}'.format(dependency, subtree[-1])
        elif isinstance(subtree, list):
            print '{} depends on {}'.format(subtree[0], 'liquidity')
        else:
            print '{} is the end of {}'.format(subtree, 'liquidity')

    # supply
    # supply_path = '{}/{}'.format(QUERIES_DIR, 'supply')
    # x = load_dependent_views(supply_path, 'supply')
    # management
    # net_revenue
    pass


load_fact_unit_economics()
