# coding=utf-8

import os
import re
from datetime import datetime, timedelta
from io import BytesIO

import boto3
import requests
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import _logger, logger

from jobs.dags.bi.crawlers import start_batch_job
from jobs.etl.crawlers.crawler_leads import CrawlerLeads

GET_LOCATIONS = \
    """
        select distinct
            type,
            lat,
            lng,
            street,
            neighborhood
        from 
            datalake_raw.crawlers
        where
            ws = '{ws}'
            and started_on = date '{started_on}'
            and regexp_like(lower(city), 's[ã|a]o paulo')
            and date(
            if(
                    updated_on != '',
                    substr(
                        updated_on,
                        1,
                        10
                    )
                )
            )>= date '{since}'
    """


def search_pattern(string, pattern, group=0):
    try:
        return pattern.search(string).group(group)
    except:
        return None


def _get_long_name(addr, addr_type):
    for component in addr:
        if addr_type in component['types']:
            return component['long_name']


@logger
def reverse_geocode(lat, lng):
    params = {
        'key': os.getenv('DATA_GOOGLE_API_KEY'),
        'latlng': "%f,%f" % (lat, lng),
        'sensor': 'false',
        'result_type': 'street_address|street_number',
        'location_type': 'ROOFTOP'
    }
    page = requests.get('https://maps.googleapis.com/maps/api/geocode/json', params=params).json()
    addr = page['results'][0]['address_components']
    route = _get_long_name(addr, 'route')
    number = _get_long_name(addr, 'street_number')
    return route, number


@logger(exclude='data')
def fillin(data):
    street_pattern = re.compile(r'-(.*)-n-(\d+)|-(.*)')
    data['street_name'] = data.street.apply(lambda x: search_pattern(x, street_pattern, 1))
    data.street_name = data.street_name.combine_first(data.street.apply(lambda x: search_pattern(x, street_pattern, 3)))
    data.street_name = data.street_name.apply(lambda x: x.replace('-', ' ') if x is not None else None)
    data['street_number'] = data.street.apply(lambda x: search_pattern(x, street_pattern, 2))

    for i, row in data.query("""street_name.isnull() or street_number.isnull()""").iterrows():
        try:
            street, number = reverse_geocode(row.lat, row.lng)
            data.loc[i, 'street_name'] = ' '.join(street.split(' ')[1:])
            data.loc[i, 'street_number'] = number
        except Exception, e:
            _logger.warn(u'm=fillin, could not retrieve street and number.')

    return data.query("""~street_name.isnull() and ~street_number.isnull()""")


@logger(exclude='data')
def csv_to_s3(data, bucket, filename):
    csv_buffer = BytesIO()
    data.to_csv(csv_buffer, index=False, encoding='utf8')
    s3 = boto3.resource('s3')
    s3.Bucket(bucket).put_object(
        Body=csv_buffer.getvalue(),
        Key=filename
    )


def crawl_cpfs(**kwargs):
    NO_LOCATIONS_MSG = 'No locations to crawl.'

    athena = AthenaClient(os.getenv('bi-datalake-s3-bucket'))
    crawler_leads = CrawlerLeads()

    ws = kwargs.get('ws', 'vivareal')
    last_date = datetime.strptime(crawler_leads.get_last_crawling_date(ws), '%Y-%m-%d')
    since = last_date - timedelta(days=kwargs.get('delta_days', 3))

    q = GET_LOCATIONS.format(ws=ws, started_on=last_date.strftime('%Y-%m-%d'), since=since.strftime('%Y-%m-%d'))

    locations = athena.execute_query_and_return_dataframe(q)
    if locations.empty:
        _logger.info(NO_LOCATIONS_MSG)
        return None

    locations = crawler_leads.cleaning(locations)

    # get to which region each lead belongs
    _logger.info('m=crawl_cpfs, checking coverage')
    locations['regions'] = locations.apply(lambda row: crawler_leads.check_coverage(row.lat, row.lng), axis=1)
    # filter out units outside our coverage area
    locations = locations[
        (locations.regions > -1) & ((~locations.type.str.contains('casa')) |
                                    locations.regions.isin(crawler_leads.house_allowed))]
    if locations.empty:
        _logger.info(NO_LOCATIONS_MSG)
        return None

    _logger.info('m=crawl_cpfs, checking neighbourhood')
    neighbourhood = kwargs.get('neighbourhood')
    if neighbourhood is not None:
        neighbourhood = crawler_leads.sanitize_text(neighbourhood)
        locations = locations[locations.neighborhood == neighbourhood]
        if locations.empty:
            _logger.info(NO_LOCATIONS_MSG)
            return None

    locations = fillin(locations)
    locations = locations.drop_duplicates(subset=['street_name', 'street_number'])

    _logger.info('m=crawl_cpfs, saving seed to job')
    sufix = '{}-{}-{}-{}.csv'.format(
        ws, last_date.strftime('%Y-%m-%d'), kwargs.get('delta_days', 3), neighbourhood or 'all')
    filename = 'raw/crawled_cpfs/source/' + sufix
    csv_to_s3(locations, os.getenv('bi-datalake-s3-bucket'), filename)

    _logger.info('m=crawl_cpfs, starting job...')
    r = start_batch_job(
        job_name='crawl_' + sufix.split('.')[0].replace('-', '_'),
        job_queue='crawling-cpfs',
        job_definition='crawling-cpfs:1',
        command=['./crawlers/get_cpfs.py',
                 's3://{}/{}'.format(os.getenv('bi-datalake-s3-bucket'), filename),
                 '--max_crawl', '1000000', '--threads', '2']
    )
    _logger.info('m=crawl_cpfs, finished with status {}. {}'.format(
        r.get('status'), '-'.join([r.get('jobId'), r.get('jobName')])))

    return locations


_ = crawl_cpfs(**{'ws': 'vivareal', 'delta_days': 3, 'neighbourhood': 'Pinheiros'})
