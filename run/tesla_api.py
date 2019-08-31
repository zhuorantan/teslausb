#!/usr/bin/python3
import argparse
import json
import requests
import time
import sys
from datetime import datetime, timedelta
# Only used for debugging.
from pprint import pprint


# Global vars for use by various functions.
base_url = 'https://owner-api.teslamotors.com/api/1/vehicles'
oauth_url = 'https://owner-api.teslamotors.com/oauth/token'
SETTINGS = {
    'DEBUG': False,
    'tesla_email': '',
    'tesla_password': '',
    'tesla_access_token': '',
    'tesla_refresh_token': '',
    'tesla_vin': '',
    # If these two stop working, updated ones can be found linked from this page:
    # https://tesla-api.timdorr.com/api-basics/authentication
    'TESLA_CLIENT_ID': '81527cff06843c8634fdc09e8ac0abefb46ac849f38fe1e431c2ef2106796384',
    'TESLA_CLIENT_SECRET': 'c7257eb71a564034f9419ee651c7d0e5f7aa6bfbd18bafb5c5c033b093bb2fa3',
}
date_format = '%Y-%m-%d %H:%M:%S'
# This dict stores the data that will be written to /mutable/tesla_api.json.
# we load its contents from disk at the start of the script, and save them back
# to the disk whenever the contents change.
tesla_api_json = {
    'access_token': '',
    'refresh_token': '',
    'vehicle_id': 0,
    'token_created_at': datetime.strptime('1970-01-01 12:00:00', date_format)
}


def _execute_request(url, method='get', data={}):
    headers = {
      'Authorization': 'Bearer {}'.format(_get_api_token()),
      'User-Agent': 'github.com/marcone/teslausb',
    }
    if method.lower() == 'get':
        response = requests.get(url, headers=headers)
    elif method.lower() == 'post':
        response = requests.post(url, headers=headers, data=data)
    else:
        raise Exception('Unknown method: {}'.format(method))
    if not response.text:
        _error("Tesla API returned nothing. Access token probably expired. Quitting...")
        sys.exit(1)
    result = response.json()

    # If there wasn't an error, return the result.
    if not result.get('error'):
        return result

    # There was an error. Log it and die.
    _error(json.dumps(result, indent=2))
    sys.exit(1)


def _get_api_token():
    """
    Retrieves the API access token, either from /mutable/tesla_api.json,
    SETTINGS, or from the Tesla API by using the credentials in SETTINGS.
    If those are also not available, kill the script, since it can't continue.
    """
    # If the token was already saved, work with that.
    if tesla_api_json['access_token']:
        # Due to what appears to be a bug with the fake-hwclock service,
        # sometimes the system thinks it's still November 2016. If that's the
        # case, we can't accurately determine the age of the token, so we just
        # use it. Later executions of the script should run after the date has
        # updated correctly, at which point we can properly compare the dates.
        now = datetime.now()
        if now.year < 2019: # This script was written in 2019.
            return tesla_api_json['access_token']

        # If it's been 30 days since the token was created, refresh it.
        if now >= tesla_api_json['token_created_at'] + timedelta(days=30):
            _refresh_api_token(tesla_api_json['refresh_token'])
        return tesla_api_json['access_token']

    # If there's no token in tesla_api_json, but the user provided a
    # token in teslausb_setup_variables.conf, refresh the provided token to save
    # the most up-to-date API data into tesla_api_json.
    elif SETTINGS['tesla_access_token']:
        _refresh_api_token(SETTINGS['tesla_refresh_token'])
        return tesla_api_json['access_token']

    # If the access token is not already stored in tesla_api_json AND the
    # user didn't provide a token pair in the teslausb_setup_variables.conf,
    # attempt to use the login credentials from teslausb_setup_variables.conf
    # to create a new token pair, if they exist.
    elif SETTINGS['tesla_email'] and SETTINGS['tesla_password']:
        # Create a new pair of tokens from the OAuth API.
        data = {
          'grant_type': 'password',
          'client_id': SETTINGS['TESLA_CLIENT_ID'],
          'client_secret': SETTINGS['TESLA_CLIENT_SECRET'],
          'email': SETTINGS['tesla_email'],
          'password': SETTINGS['tesla_password']
        }
        headers = {
            'User-Agent': 'github.com/marcone/teslausb',
        }
        _log('Retrieving new API token...')
        # Useful for debugging credential issues
        _log("data = {}".format(data))
        response = requests.post(oauth_url, headers=headers, data=data)
        result = response.json()
        if 'access_token' not in result:
            _error('Unable to create access token:')
            _error(result)
            sys.exit(1)
        _log('Success! New Tokens:\naccess: {}\nrefresh: {}'.format(
            result['access_token'], result['refresh_token']
        ))
        # Write the tokens to tesla_api_json, which is where the rest of the
        # code retrieves them from.
        tesla_api_json['access_token'] = result['access_token']
        tesla_api_json['refresh_token'] = result['refresh_token']
        tesla_api_json['token_created_at'] = datetime.now()
        _write_tesla_api_json()
        return tesla_api_json['access_token']

    _error('Unable to perform Tesla API functions: no credentials or token.')
    sys.exit(1)


def _refresh_api_token(refresh_token):
    """
    Given the specified refresh token, perform a refresh and store the new
    access_token and refresh_token into tesla_api_json.
    """
    # Refresh the token.
    data = {
      'grant_type': 'refresh_token',
      'client_id': SETTINGS['TESLA_CLIENT_ID'],
      'client_secret': SETTINGS['TESLA_CLIENT_SECRET'],
      'refresh_token': refresh_token,
    }
    headers = {
        'User-Agent': 'github.com/marcone/teslausb',
    }
    _log('Refreshing API token...')
    response = requests.post(oauth_url, headers=headers, data=data)
    result = response.json()
    if 'access_token' not in result:
        _error('Unable to refresh access token:')
        _error(result)
        sys.exit(1)
    _log('Success! New Tokens:\naccess: {}\nrefresh: {}'.format(
        result['access_token'], result['refresh_token']
    ))
    tesla_api_json['access_token'] = result['access_token']
    tesla_api_json['refresh_token'] = result['refresh_token']
    tesla_api_json['token_created_at'] = datetime.now()
    _write_tesla_api_json()


def _get_vehicle_id():
    """
    Put the vehicle's ID into tesla_api_json['vehicle_id'].
    """
    # If it was already set by _load_tesla_api_json(), we're done.
    if tesla_api_json['vehicle_id']:
        return

    # Call list_vehicles() and use the provided VIN to get the vehicle ID.
    result = list_vehicles()
    for vehicle_dict in result['response']:
        if vehicle_dict['vin'] == SETTINGS['tesla_vin']:
            tesla_api_json['vehicle_id'] = vehicle_dict['id_s']
            _log('Retrieved Vehicle ID from Tesla API.')
            _write_tesla_api_json()
            return

    _error('Unable to retrieve vehicle ID: Unknown VIN. Cannot continue.')
    sys.exit(1)

def _load_tesla_api_json():
    """
    Load the data stored in /mutable/tesla_api.json, if it exists.
    If it doesn't exist, write a file to that location with default values.
    """
    try:
        with open('/mutable/tesla_api.json', 'r') as f:
            _log('Loading mutable data from disk...')
            json_string = f.read()
    except FileNotFoundError:
        # Write a dict with the default data to the file.
        _log("Mutable data didn't exist, writing defaults...")
        _write_tesla_api_json()
    else:
        def datetime_parser(dct):
            # Converts any string with the appropriate format in the parsed JSON
            # dict into a datetime object.
            for k, v in dct.items():
                try:
                    dct[k] = datetime.strptime(v, date_format)
                except (TypeError, ValueError):
                    pass
            return dct

        # Need to declare this as a global since we assign to it directly.
        global tesla_api_json
        tesla_api_json = json.loads(json_string, object_hook=datetime_parser)


def _write_tesla_api_json():
    """
    Write the contents of the tesla_api_json dict to /mutable/tesla_api.json.
    """
    def convert_dt(obj):
        # Converts datetime objects into 'YYYY-MM-DD HH:MM:SS' strings, since
        # json.dumps() can't serialize them itself.
        if isinstance(obj, datetime):
            return obj.strftime(date_format)

    with open('/mutable/tesla_api.json', 'w') as f:
        _log('Writing /mutable/tesla_api.json...')
        json_string = json.dumps(tesla_api_json, indent=2, default=convert_dt)
        f.write(json_string);

def _get_log_timestamp():
    # I can't figure out how to get a timezone aware version of now() in
    # Python 2.7 without pytz, so I kludged this together. It outputs the
    # same timestamp format as the other logging done by TeslaUSB's code.
    zone = time.tzname[time.daylight]
    return datetime.now().strftime('%a %d %b %H:%M:%S {} %Y'.format(zone))

def _log(msg, flush=True):
    if SETTINGS['DEBUG']:
        print("{}: {}".format(_get_log_timestamp(), msg), flush=flush)


def _error(msg, flush=True):
    """
    It's _log(), but for errors, so it always prints.
    """
    print("{}: {}".format(_get_log_timestamp(), msg), flush=flush)


######################################
# API GET Functions
######################################
def list_vehicles():
    return _execute_request(base_url)


def get_charge_state():
    return _execute_request(
        '{}/{}/data_request/charge_state'.format(base_url, tesla_api_json['vehicle_id'])
    )


def get_climate_state():
    return _execute_request(
        '{}/{}/data_request/climate_state'.format(base_url, tesla_api_json['vehicle_id'])
    )


def get_drive_state():
    return _execute_request(
        '{}/{}/data_request/drive_state'.format(base_url, tesla_api_json['vehicle_id'])
    )


def get_gui_settings():
    return _execute_request(
        '{}/{}/data_request/gui_settings'.format(base_url, tesla_api_json['vehicle_id'])
    )


def get_vehicle_state():
    return _execute_request(
        '{}/{}/data_request/vehicle_state'.format(base_url, tesla_api_json['vehicle_id'])
    )


######################################
# Custom Functions
######################################
def get_odometer():
    data = get_vehicle_state()
    return int(data['response']['odometer'])


def is_car_locked():
    data = get_vehicle_state()
    return data['response']['locked']


######################################
# API POST Functions
######################################
def wake_up_vehicle():
    # It's not really an error, but I want to make sure this always prints,
    # even if DEBUG is False. Also I need the timestamp.
    _error('Sending wakeup API command...')
    result = _execute_request(
        '{}/{}/wake_up'.format(base_url, tesla_api_json['vehicle_id']),
        method='POST'
    )
    return result['response']['state']


def set_charge_limit(percent):
    return _execute_request(
        '{}/{}/command/set_charge_limit'.format(base_url, tesla_api_json['vehicle_id']),
        method='POST',
        data={'percent': percent}
    )


######################################
# MAIN
######################################
def main():
    # Build the list of available Tesla API function names by getting the
    # callables from globals() and skipping the non-API functions.
    non_api_names = ['main', 'pprint']
    function_names = []
    for name, func in globals().items():
        if (callable(func)
            and not name.startswith('_')
            and not name in non_api_names
        ):
            function_names.append(name)
    function_names_string = '\n'.join(function_names)

    # Parse the CLI arguments.
    parser = argparse.ArgumentParser()
    parser.add_argument(
        'function',
        help="The name of the function to run. Available functions are:\n {}".format(function_names_string))
    parser.add_argument(
        '--arguments',
        help="Add arguments to the function by passing comma-separated key:value pairs."
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Print debug output."
    )
    args = parser.parse_args()

    SETTINGS['DEBUG'] = args.debug

    # We call this now so DEBUG will be set correctly.
    _load_tesla_api_json()

    # Apply any arguments that the user may have provided.
    kwargs = {}
    if args.arguments:
        for kwarg_string in [arg.strip() for arg in args.arguments.split(',')]:
            key, value = kwarg_string.split(':')
            kwargs[key] = value
    # Render the arguments as a POST body.
    kwargs_string = ''
    if kwargs:
        kwargs_string = ', '.join(
            '{}={}'.format(key, value) for key, value in kwargs.items()
        )

    # Retrieve the setup variables, which is where the account credentials
    # or bearer token, and the VIN are stored. Since teslausb_setup_variables.conf
    # is actually a shell script, rather than a ConfigParser file, we have to
    # parse it manually.
    with open('/root/teslausb_setup_variables.conf', 'r') as conf_file:
        conf_lines = [
            line.strip()
            for line in conf_file.read().split('\n')
            if line.strip() and not line.strip().startswith('#')
        ]
    for line in conf_lines:
        setting = line.split('=')
        # Strip leading/trailing whitespace and the "export " part off of "export setting_name=value"
        setting_name = setting[0].replace('export ', '').strip()
        # Strip leading/trailing whitespace, " and ' surrounding bash script variable values
        setting_value = setting[1].strip(" \"'")
        SETTINGS[setting_name] = setting_value

    # We need to call this before calling any API function, because those need
    # to know the Vehicle ID before they call _execute_request()
    _get_vehicle_id()

    # Get the function by name from the globals() dict and call it with the
    # specified args.
    function = globals()[args.function]
    _log('Calling {}({})...'.format(args.function, kwargs_string))
    result = function(**kwargs)

    # Write the output of the API call to stdout, if DEBUG is true.
    _log(json.dumps(result, indent=2))


main()
