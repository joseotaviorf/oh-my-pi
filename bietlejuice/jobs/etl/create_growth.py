import os
import sys

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, '../../'))

from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb

measures = {
    'closing': [
        'ongoing_contracts'
    ],
    'demand': [
        'approved_by_insurer',
        'documentation_sent',
        'offerers',
        'offerers_approved',
        'offerers_sent_doc',
        'offers_approved',
        'offers_submitted',
        'tenant_prospects',
        'tenants',
        'visitors',
        'visits_booked',
        'visits_completed'
    ],
    'supply': [
        'leads',
        'new_listings',
        'opportunities',
        'prospects',
        'qualifieds'
    ]
}


filters = [
    'all',
    'city',
    'region'
]

period = [
    'day',
    'week',
    'month',
    'year'
]


def get_query_from_file_name(file_name):
    print 'reading file: {}'.format(file_name)

    try:
        with open(file_name) as f:
            return f.read()
    except IOError:
        return ''


measure_all_query = get_query_from_file_name('../../db/3.dw/public/queries/growth/new/measure_all.sql')
for funnel in measures:
    for m in measures[funnel]:
        for f in filters:
            for p in period:
                prefix_file = '../../db/3.dw/public/queries/growth/new/{}/{}/{}/{}_prefix_beginning.sql'.format(funnel, m, f, p)
                prefix_middle_file = '../../db/3.dw/public/queries/growth/new/{}/{}/{}/{}_prefix_middle.sql'.format(funnel, m, f, p)
                suffix_middle_file = '../../db/3.dw/public/queries/growth/new/{}_middle_suffix.sql'.format(p)
                suffix_file = '../../db/3.dw/public/queries/growth/new/{}_suffix.sql'.format(p)

                prefix = get_query_from_file_name(prefix_file)
                prefix_middle = get_query_from_file_name(prefix_middle_file) if p != 'day' else ''
                suffix_middle = get_query_from_file_name(suffix_middle_file) if p != 'day' else ''
                suffix = get_query_from_file_name(suffix_file)

                query = 'create table growth.{}_{}_{} as\n'.format(m, f, p) + prefix + suffix_middle + prefix_middle + suffix
                print query

                print '\nDropping table growth.{}_{}_{}\n'.format(m, f, p)
                BaseETL.execute_command(
                    command='drop table if exists growth.{}_{}_{};'.format(m, f, p),
                    commit=True,
                    db_enum=EnumDb.BI_DW
                )

                print '\nCreating table growth.{}_{}_{}\n'.format(m, f, p)
                BaseETL.execute_command(
                    command=query,
                    commit=True,
                    db_enum=EnumDb.BI_DW
                )

        print '\nDropping table growth.{}_all\n'.format(m)
        BaseETL.execute_command(
            command='drop table if exists growth.{}_all;'.format(m),
            commit=True,
            db_enum=EnumDb.BI_DW
        )

        print '\nCreating table growth.{}_all\n'.format(m)
        BaseETL.execute_command(
            command=measure_all_query.format(m),
            commit=True,
            db_enum=EnumDb.BI_DW
        )
