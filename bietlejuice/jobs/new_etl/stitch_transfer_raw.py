import boto3
from qa_python_utils.default_logger import logger, _logger


class StitchTransferRaw(object):
    @logger
    def __init__(self, bucket, execution_date, integration):
        self.s3_client = boto3.resource('s3')
        self.bucket = bucket
        self.yesterday = execution_date
        self.integration = integration
        self.prefix = 'stitch/{date}/{integration}' \
            .format(date=self.yesterday.strftime('%Y-%m-%d'), integration=integration)
        self.suffix = '.jsonl'

    @logger
    def copy_files(self):
        for key in self.__fetch_files():
            new_key = self.__build_key(key)
            _logger.debug('m=copy_files, msg=creating new copy_source with origin bucket and origin key, key={}'
                          .format(new_key))
            copy_source = dict(
                Bucket=self.bucket,
                Key=key
            )

            _logger.info('m=copy_files, msg=copying: {}'.format(copy_source))
            try:
                self.s3_client.meta.client.copy_object(
                    CopySource=copy_source,
                    Bucket=self.bucket,
                    Key=new_key
                )
            except Exception as error:
                raise RuntimeError('m=copy_files, msg={}'.format(error.message))

    @logger
    def __fetch_files(self):
        _logger.info('m=__fetch_files, msg=reading files from stitch bucket')
        kwargs = {
            'Bucket': self.bucket,
            'Prefix': self.prefix
        }
        _logger.info('m=__fetch_files, msg=getting paginated files from s3 bucket')
        while True:
            response = self.s3_client.meta.client.list_objects_v2(**kwargs)

            if not response['Contents']:
                _logger.info('m=__fetch_files, msg=no files fetched')
                break

            for s3_object in response['Contents']:
                key = s3_object['Key']
                if key.startswith(self.prefix) and key.endswith(self.suffix):
                    yield key

            try:
                kwargs['ContinuationToken'] = response['NextContinuationToken']
            except KeyError:
                _logger.info('m=__fetch_files, msg=no more pages found')
                break

    def __build_key(self, key):
        tokens = key.split('/')
        extract_date = tokens[1]
        account = tokens[2].replace('{}_'.format(self.integration), '')
        table = tokens[3]
        file_name = tokens[-1]

        _logger.info('m=move_files_from_stitch_to_raw, msg=bulding new path to copy files')
        return 'raw/{integration}/{table}/acc={account}/dt={extract_date}/{file_name}'.format(
            integration=self.integration,
            table=table,
            account=account,
            extract_date=extract_date,
            file_name=file_name)
