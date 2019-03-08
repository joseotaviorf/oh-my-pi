from abc import ABCMeta
from abc import abstractmethod
from elasticsearch import Elasticsearch
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('ESLogsFetcher')


class ESLogsFetcher(object):
    __metaclass__ = ABCMeta

    def __init__(self, es_logs__hostname):
        self.es = Elasticsearch(es_logs__hostname)
        self.index = None
        self.doc_type = None
        self.body = None

    @abstractmethod
    def build_query(self):
        raise NotImplementedError

    @abstractmethod
    def run(self):
        raise NotImplementedError

    @logger
    def __search(self, from_=0, size=10, scroll=None):
        result = self.es.search(
            index=self.index,
            doc_type=self.doc_type,
            body=self.body,
            from_=from_,
            size=size,
            scroll=scroll
        )
        return result

    @logger
    def __paginate_results(self, total_size, step_size, scroll):
        search_result = self.__search(
            size=step_size,
            scroll=scroll
        )

        scroll_id = search_result['_scroll_id']
        scroll_size = len(search_result['hits']['hits'])
        batch_size = 0
        while scroll_size > 0 and batch_size <= total_size:
            # log pagination state
            msg = (
                'm=ESLogsFetcher.__paginate_results, ' +
                'scroll_size={}, ' +
                'batch_size={}, ' +
                'total_size={}, ' +
                'scroll_id={}'
            ).format(
                scroll_size,
                batch_size,
                total_size,
                scroll_id
            )
            logger.info(msg)

            # get scroll page
            search_result = self.es.scroll(
                scroll_id=scroll_id,
                scroll=scroll)

            # process results
            yield search_result

            # update scroll id
            scroll_id = search_result['_scroll_id']

            # update size counters
            scroll_size = len(search_result['hits']['hits'])
            batch_size += scroll_size

    @logger
    def fetch_all(self, step_size=10, max_size=None, scroll=None):
        # first search sets total amount of hits
        search_result = self.__search()
        total_size = search_result['hits']['total']
        logger.info(
            'm=ESLogsFetcher.fetch_all, hits_total={}'.format(total_size))

        # limit total_size with max_size
        if max_size is None:
            max_size = total_size
        total_size = min(total_size, max_size)

        # set default scroll consistency duration to 5 minutes
        if scroll is None:
            scroll = '1m'

        return self.__paginate_results(
            total_size=total_size,
            step_size=step_size,
            scroll=scroll
        )
