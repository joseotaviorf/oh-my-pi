import os


def get_keys(file_path=os.path.dirname(os.path.realpath(__file__))):
    keys = []
    filename = file_path + '/amplitude.apps.properties'
    print('Properties File: ' + filename)
    with open(filename, 'r') as f:
        lines = f.readlines()
        for l in lines:
            if l[-1] == '\n':
                l = l[0:-1]  # remove \n
            if len(l) > 0 and l[0] != '#':
                print('Property: ' + l)
                appid_keys = l.split('=')
                if appid_keys:
                    k = appid_keys[1].split(',')
                    if k:
                        app_key = k[0]
                        secret_key = k[1]
                        keys.append({'app': appid_keys[0], 'app_key': app_key, 'secret_key': secret_key})

    return keys
