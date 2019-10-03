from conftest import pytest, mock, GithubService


class TestGithubPullRequests(object):

    @mock.patch.object(GithubService, 'get_json_response',
                       return_value={
                           'data': {
                               'repositoryOwner': {
                                   'repository': None
                               }
                           }
                       })
    def test_extract_pull_requests_with_repository_none(self, mock_get_json_response, github_pull_requests):
        # act & assert
        with pytest.raises(RuntimeError):
            github_pull_requests.extract_pull_requests()

    @mock.patch.object(GithubService, 'get_json_response',
                       return_value={
                           'data': {
                               'repositoryOwner': {
                                   'repository': {
                                       'pullRequests': {
                                           'edges': []
                                       }
                                   }
                               }
                           }
                       })
    def test_extract_pull_requests_with_empty_edges(self, mock_get_json_response, github_pull_requests):
        # act
        no_reviewed_prs, reviewed_prs, approved_prs = github_pull_requests.extract_pull_requests()

        # assert
        assert (not no_reviewed_prs) and (not reviewed_prs) and (not approved_prs)

    @pytest.mark.parametrize('review_edges, approved_prs_length',
                             [[[], 0],
                              [[{'node': {'state': 'COMMENTED'}}], 0],
                              [[{'node': {'state': 'CHANGES_REQUESTED'}}], 0]])
    @mock.patch.object(GithubService, 'get_json_response')
    def test_extract_pull_requests_with_no_approved_prs(self, mock_get_json_response, github_pull_requests,
                                                        review_edges, approved_prs_length):
        # arrange
        mock_get_json_response.return_value = {
            'data': {
                'repositoryOwner': {
                    'repository': {
                        'pullRequests': {
                            'edges': [{
                                'node': {
                                    'title': 'title',
                                    'author': {
                                        'login': 'login'
                                    },
                                    'url': 'url',
                                    'reviews': {
                                        'edges': review_edges
                                    }
                                }
                            }]
                        }
                    }
                }
            }
        }

        # act
        no_reviewed_prs, reviewed_prs, approved_prs = github_pull_requests.extract_pull_requests()

        # assert
        assert no_reviewed_prs or reviewed_prs
        assert len(approved_prs) == approved_prs_length

    @mock.patch.object(GithubService, 'get_json_response', return_value={
        'data': {
            'repositoryOwner': {
                'repository': {
                    'pullRequests': {
                        'edges': [{
                            'node': {
                                'title': 'title',
                                'author': {
                                    'login': mock.ANY
                                },
                                'url': mock.ANY,
                                'reviews': {
                                    'edges': [{
                                        'node': {
                                            'state': 'APPROVED'
                                        }
                                    }]
                                }
                            }
                        }]
                    }
                }
            }
        }
    })
    def test_extract_pull_requests_with_approved_prs(self, mock_get_json_response, github_pull_requests):
        # act
        no_reviewed_prs, reviewed_prs, approved_prs = github_pull_requests.extract_pull_requests()

        # assert
        assert not no_reviewed_prs and not reviewed_prs
        assert approved_prs
