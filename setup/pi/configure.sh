#!/bin/bash -eu

if [ "${BASH_SOURCE[0]}" != "$0" ]
then
  echo "${BASH_SOURCE[0]} must be executed, not sourced"
  return 1 # shouldn't use exit when sourced
fi

function log_progress () {
  if declare -F setup_progress > /dev/null
  then
    setup_progress "configure: $1"
    return
  fi
  echo "configure: $1"
}

if [ "${FLOCKED:-}" != "$0" ]
then
  PARENT="$(ps -o comm= $PPID)"
  if [ "$PARENT" != "setup-teslausb" ]
  then
    log_progress "STOP: $0 must be called from setup-teslausb: $PARENT"
    exit 1
  fi

  if FLOCKED="$0" flock -en -E 99 "$0" "$0" "$@" || case "$?" in
  99) echo already running
      exit 99
      ;;
  *)  exit $?
      ;;
  esac
  then
    # success
    exit 0
  fi
fi

ARCHIVE_SYSTEM=${ARCHIVE_SYSTEM:-none}

function check_variable () {
    local var_name="$1"
    if [ -z "${!var_name+x}" ]
    then
        log_progress "STOP: Define the variable $var_name like this: export $var_name=value"
        exit 1
    fi
}

# as of March 2021, Raspberry Pi OS still includes a 3 year old version of
# rsync, which has a bug (https://bugzilla.samba.org/show_bug.cgi?id=10494)
# that breaks archiving from snapshots.
# Check that the default rsync works correctly, and install a newer version
# if needed.
function check_default_rsync {
  hash rsync

  rm -rf /tmp/rsynctest
  mkdir -p /tmp/rsynctest/src /tmp/rsynctest/dst
  echo testfile > /tmp/testfile.dat
  echo testfile.dat > /tmp/filelist
  ln -s /tmp/testfile.dat /tmp/rsynctest/src/
  if rsync -avhRL --remove-source-files --no-perms --omit-dir-times --files-from=/tmp/filelist /tmp/rsynctest/src/ /tmp/rsynctest/dst
  then
    if [ -s /tmp/rsynctest/dst/testfile.dat ] && ! [ -e /tmp/rsynctest/src/testfile.dat ]
    then
      rm -rf /tmp/rsynctest
      return 0
    fi
  fi
  return 1
}

function check_rsync {
  if check_default_rsync
  then
    log_progress "rsync seems to work OK"
    return 0
  fi

  log_progress "default rsync doesn't work, installing prebuilt 3.2.3"
  if curl -L --fail -o /usr/local/bin/rsync https://github.com/marcone/rsync/releases/download/v3.2.3-rpi/rsync
  then
    chmod a+x /usr/local/bin/rsync
    apt install -y libxxhash0
    if check_default_rsync
    then
      log_progress "rsync works OK now"
      return 0
    fi
  fi

  log_progress "STOP: rsync doesn't work correctly"
  exit 1
}

function check_archive_configs () {
    log_progress "Checking archive configs: "

    case "$ARCHIVE_SYSTEM" in
        rsync)
            check_variable "RSYNC_USER"
            check_variable "RSYNC_SERVER"
            check_variable "RSYNC_PATH"
            export ARCHIVE_SERVER="$RSYNC_SERVER"
            check_rsync
            ;;
        rclone)
            check_variable "RCLONE_DRIVE"
            check_variable "RCLONE_PATH"
            export ARCHIVE_SERVER="8.8.8.8" # since it's a cloud hosted drive we'll just set this to google dns
            ;;
        cifs)
            check_variable "SHARE_NAME"
            check_variable "SHARE_USER"
            check_variable "SHARE_PASSWORD"
            check_variable "ARCHIVE_SERVER"
            check_rsync
            ;;
        none)
            export ARCHIVE_SERVER=localhost
            ;;
        *)
            log_progress "STOP: Unrecognized archive system: $ARCHIVE_SYSTEM"
            exit 1
            ;;
    esac

    log_progress "done"
}

function get_archive_module () {

    case "$ARCHIVE_SYSTEM" in
        rsync)
            echo "run/rsync_archive"
            ;;
        rclone)
            echo "run/rclone_archive"
            ;;
        cifs)
            echo "run/cifs_archive"
            ;;
        none)
            echo "run/none_archive"
            ;;
        *)
            log_progress "Internal error: Attempting to configure unrecognized archive system: $ARCHIVE_SYSTEM"
            exit 1
            ;;
    esac
}

function install_and_configure_tesla_api () {
  # Install the tesla_api.py script only if the user provided credentials for its use.

  if [ -e /root/bin/tesla_api.py ]
  then
    # if tesla_api.py already exists, update it
    log_progress "Updating tesla_api.py"
    get_script /root/bin tesla_api.py run
    install_python3_pip
    pip3 install teslapy
    # check if the json file needs to be updated
    readonly json=/mutable/tesla_api.json
    if [ -e $json ] && ! grep -q '"id"' $json
    then
      log_progress "Updating tesla_api.py config file"
      sed -i 's/"vehicle_id"/"id"/' $json
      sed -i 's/"$/",\n  "vehicle_id": 0/' $json
      # Call script to fill in the empty vehicle_id field
      if ! /root/bin/tesla_api.py list_vehicles
      then
        log_progress "tesla_api.py config update failed"
      fi
    fi
  elif [[ ( -n "${TESLA_REFRESH_TOKEN:+x}" ) ]]
  then
    log_progress "Installing tesla_api.py"
    get_script /root/bin tesla_api.py run
    install_python3_pip
    pip3 install teslapy
    # Perform the initial authentication
    mount /mutable || log_progress "Failed to mount /mutable"
    if ! /root/bin/tesla_api.py list_vehicles
    then
      log_progress "tesla_api.py setup failed"
    fi
  else
    log_progress "Skipping tesla_api.py install because no credentials were provided"
  fi
}

function install_archive_scripts () {
  local install_path="$1"
  local archive_module="$2"

  log_progress "Installing base archive scripts into $install_path"
  get_script "$install_path" archiveloop run
  get_script "$install_path" waitforidle run
  get_script "$install_path" remountfs_rw run
  get_script "$install_path" awake_start run
  get_script "$install_path" awake_stop run
  install_and_configure_tesla_api
  log_progress "Installing archive module scripts"
  get_script /tmp verify-and-configure-archive.sh "$archive_module"
  get_script "$install_path" archive-clips.sh "$archive_module"
  get_script "$install_path" connect-archive.sh "$archive_module"
  get_script "$install_path" disconnect-archive.sh "$archive_module"
  get_script "$install_path" archive-is-reachable.sh "$archive_module"
  if [ -n "${MUSIC_SHARE_NAME:+x}" ] && grep cifs <<< "$archive_module"
  then
    get_script "$install_path" copy-music.sh "$archive_module"
  fi
}

function install_python3_pip () {
  if ! command -v pip3 &> /dev/null
  then
    setup_progress "Installing support for python packages..."
    apt-get --assume-yes install python3-pip
  fi
}

function install_sns_packages () {
  install_python3_pip
  setup_progress "Installing sns python packages..."
  pip3 install boto3
}

function install_matrix_packages () {
  install_python3_pip
  setup_progress "Installing matrix python packages..."
  pip3 install matrix-nio
}

function check_pushover_configuration () {
  if [ "${PUSHOVER_ENABLED:-false}" = "true" ]
  then
    if [ -z "${PUSHOVER_USER_KEY+x}" ] || [ -z "${PUSHOVER_APP_KEY+x}"  ]
    then
      log_progress "STOP: You're trying to setup Pushover but didn't provide your User and/or App key."
      log_progress "Define the variables like this:"
      log_progress "export PUSHOVER_USER_KEY=put_your_userkey_here"
      log_progress "export PUSHOVER_APP_KEY=put_your_appkey_here"
      exit 1
    elif [ "${PUSHOVER_USER_KEY}" = "put_your_userkey_here" ] || [  "${PUSHOVER_APP_KEY}" = "put_your_appkey_here" ]
    then
      log_progress "STOP: You're trying to setup Pushover, but didn't replace the default User and App key values."
      exit 1
    fi
  fi
}

function check_gotify_configuration () {
  if [ "${GOTIFY_ENABLED:-false}" = "true" ]
  then
    if [ -z "${GOTIFY_DOMAIN+x}" ] || [ -z "${GOTIFY_APP_TOKEN+x}" ] || [ -z "${GOTIFY_PRIORITY+x}" ]
    then
      log_progress "STOP: You're trying to setup Gotify but didn't provide your Domain, App token or priority."
      log_progress "Define the variables like this:"
      log_progress "export GOTIFY_DOMAIN=https://gotify.domain.com"
      log_progress "export GOTIFY_APP_TOKEN=put_your_token_here"
      log_progress "export GOTIFY_PRIORITY=5"
      exit 1
    elif [ "${GOTIFY_DOMAIN}" = "https://gotify.domain.com" ] || [  "${GOTIFY_APP_TOKEN}" = "put_your_token_here" ]
    then
      log_progress "STOP: You're trying to setup Gotify, but didn't replace the default Domain and/or App token values."
      exit 1
    fi
  fi
}

function check_discord_configuration() {
  if [ "${DISCORD_ENABLED:-false}" = "true" ]
  then
    if [ -z "${DISCORD_WEBHOOK_URL+x}" ]
    then
      log_progress "STOP: You're trying to setup Discord but didn't provide your Webhook URL."
      log_progress "Define the variables like this:"
      log_progress "export DISCORD_WEBHOOK_URL=put_your_webhook_url_here"
      exit 1
    elif [ "${DISCORD_WEBHOOK_URL}" = "put_your_webhook_url_here" ]
    then
      log_progress "STOP: You're trying to setup Discord, but didn't replace the default Webhook URL"
      exit 1
    fi
  fi
}

function check_ifttt_configuration () {
  if [ "${IFTTT_ENABLED:-false}" = "true" ]
  then
    if [ -z "${IFTTT_EVENT_NAME+x}" ] || [ -z "${IFTTT_KEY+x}"  ]
    then
      log_progress "STOP: You're trying to setup IFTTT but didn't provide your Event Name and/or key."
      log_progress "Define the variables like this:"
      log_progress "export IFTTT_EVENT_NAME=put_your_event_name_here"
      log_progress "export IFTTT_KEY=put_your_key_here"
      exit 1
    elif [ "${IFTTT_EVENT_NAME}" = "put_your_event_name_here" ] || [  "${IFTTT_KEY}" = "put_your_key_here" ]
    then
      log_progress "STOP: You're trying to setup IFTTT, but didn't replace the default Event Name and/or key values."
      exit 1
    fi
  fi
}

function check_webhook_configuration () {
  if [ "${WEBHOOK_ENABLED:-false}" = "true" ]
  then
    if [ -z "${WEBHOOK_URL+x}"  ]
    then
      log_progress "STOP: You're trying to setup a Webhook but didn't provide your webhook url."
      log_progress "Define the variable like this:"
      log_progress "export WEBHOOK_URL=http://domain/path/"
      exit 1
    elif [ "${WEBHOOK_URL}" = "http://domain/path/" ]
    then
      log_progress "STOP: You're trying to setup a Webhook, but didn't replace the default url."
      exit 1
    fi
  fi
}

function check_slack_configuration () {
  if [ "${SLACK_ENABLED:-false}" = "true" ]
  then
    if [ -z "${SLACK_WEBHOOK_URL+x}"  ]
    then
      log_progress "STOP: You're trying to setup a Slack webhook but didn't provide your webhook url."
      log_progress "Define the variable like this:"
      log_progress "export SLACK_WEBHOOK_URL=http://domain/path/"
      exit 1
    elif [ "${SLACK_WEBHOOK_URL}" = "http://domain/path/" ]
    then
      log_progress "STOP: You're trying to setup a Slack webhook, but didn't replace the default url."
      exit 1
    fi
  fi
}

function check_matrix_configuration () {
  if [ "${MATRIX_ENABLED:-false}" = "true" ]
  then
      if [ -z "${MATRIX_SERVER_URL+x}"  ] || [ -z "${MATRIX_USERNAME+x}"  ] || [ -z "${MATRIX_PASSWORD+x}"  ] || [ -z "${MATRIX_ROOM+x}"  ]
      then
          log_progress "STOP: You're trying to setup Matrix but didn't provide your server URL, username, password or room."
          log_progress "Define the variable like this:"
          log_progress "export MATRIX_SERVER_URL=https://matrix.org"
          log_progress "export MATRIX_USERNAME=put_your_matrix_username_here"
          log_progress "export MATRIX_PASSWORD='put_your_matrix_password_here'"
          log_progress "export MATRIX_ROOM='put_the_matrix_target_room_id_here'"
          exit 1
      elif [ "${MATRIX_USERNAME}" = "put_your_matrix_username_here" ] || [ "${MATRIX_PASSWORD}" = "put_your_matrix_password_here" ] ||[ "${MATRIX_ROOM}" = "put_the_matrix_target_room_id_here" ]
      then
          log_progress "STOP: You're trying to setup Matrix, but didn't replace the default username, password or target room."
          exit 1
      fi
  fi
}

function check_sns_configuration () {
  if [ "${SNS_ENABLED:-false}" = "true" ]
  then
    if [ -z "${AWS_ACCESS_KEY_ID:+x}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:+x}" ] || [ -z "${AWS_SNS_TOPIC_ARN:+x}" ]
    then
      echo "STOP: You're trying to setup AWS SNS but didn't provide your User and/or App key and/or topic ARN."
      echo "Define the variables like this:"
      echo "export AWS_ACCESS_KEY_ID=put_your_accesskeyid_here"
      echo "export AWS_SECRET_ACCESS_KEY=put_your_secretkey_here"
      echo "export AWS_SNS_TOPIC_ARN=put_your_sns_topicarn_here"
      exit 1
    elif [ "${AWS_ACCESS_KEY_ID}" = "put_your_accesskeyid_here" ] || [ "${AWS_SECRET_ACCESS_KEY}" = "put_your_secretkey_here" ] || [ "${AWS_SNS_TOPIC_ARN}" = "put_your_sns_topicarn_here" ]
    then
      echo "STOP: You're trying to setup SNS, but didn't replace the default values."
      exit 1
    fi
  fi
}

function check_telegram_configuration () {
  if [ "${TELEGRAM_ENABLED:-false}" = "true" ]
  then
    if [ -z "${TELEGRAM_BOT_TOKEN+x}"  ] || [ -z "${TELEGRAM_CHAT_ID:+x}" ]
    then
      log_progress "STOP: You're trying to setup Telegram but didn't provide your Bot Token or Chat id."
      echo "Define the variables in config file like this:"
      echo "export TELEGRAM_CHAT_ID=123456789"
      echo "export TELEGRAM_BOT_TOKEN=bot123456789:abcdefghijklmnopqrstuvqxyz987654321"
      exit 1
    elif [ "${TELEGRAM_BOT_TOKEN}" = "bot123456789:abcdefghijklmnopqrstuvqxyz987654321" ] || [ "${TELEGRAM_CHAT_ID}" = "123456789" ]
    then
      log_progress "STOP: You're trying to setup Telegram, but didn't replace the default values."
      exit 1
    fi
  fi
}

function configure_pushover () {
  # remove legacy file
  rm -f /root/.teslaCamPushoverCredentials

  if [ "${PUSHOVER_ENABLED:-false}" = "true" ]
  then
    log_progress "Pushover enabled"
  else
    log_progress "Pushover not enabled."
  fi
}

function configure_gotify () {
  # remove legacy file
  rm -f /root/.teslaCamGotifySettings

  if [ "${GOTIFY_ENABLED:-false}" = "true" ]
  then
    log_progress "Gotify enabled."
  else
    log_progress "Gotify not enabled."
  fi
}

function configure_discord () {
  if [ "${DISCORD_ENABLED:-false}" = "true" ]
  then
    log_progress "Discord enabled."
  else
    log_progress "Discord not enabled."
  fi
}

function configure_ifttt () {
  # remove legacy file
  rm -f /root/.teslaCamIftttSettings

  if [ "${IFTTT_ENABLED:-false}" = "true" ]
  then
    log_progress "IFTTT enabled."
  else
    log_progress "IFTTT not enabled."
  fi
}

function configure_telegram () {
  if [ "${TELEGRAM_ENABLED:-false}" = "true" ]
  then
    log_progress "Telegram enabled."
  else
    log_progress "Telegram not enabled."
  fi
}

function configure_webhook () {
  # remove legacy file
  rm -f /root/.teslaCamWebhookSettings

  if [ "${WEBHOOK_ENABLED:-false}" = "true" ]
  then
    log_progress "Webhook enabled."
  else
    log_progress "Webhook not enabled."
  fi
}

function configure_slack () {
  if [ "${SLACK_ENABLED:-false}" = "true" ]
  then
    log_progress "Slack enabled."
  else
    log_progress "Slack not enabled."
  fi
}

function configure_matrix () {
  if [ "${MATRIX_ENABLED:-false}" = "true" ]
  then
    log_progress "Enabling Matrix"
    install_matrix_packages
  else
    log_progress "Matrix not configured."
  fi
}

function configure_sns () {
  # remove legacy file
  rm -f /root/.teslaCamSNSTopicARN

  if [ "${SNS_ENABLED:-false}" = "true" ]
  then
    log_progress "Enabling SNS"
    mkdir -p /root/.aws

    rm -f /root/.aws/credentials

    echo "[default]" > /root/.aws/config
    echo "region = $AWS_REGION" >> /root/.aws/config

    install_sns_packages
  else
    log_progress "SNS not configured."
  fi
}

function check_and_configure_pushover () {
  check_pushover_configuration

  configure_pushover
}

function check_and_configure_gotify () {
  check_gotify_configuration

  configure_gotify
}

function check_and_configure_discord () {
  check_discord_configuration

  configure_discord
}

function check_and_configure_ifttt () {
  check_ifttt_configuration

  configure_ifttt
}

function check_and_configure_webhook () {
  check_webhook_configuration

  configure_webhook
}

function check_and_configure_slack () {
  check_slack_configuration

  configure_slack
}

function check_and_configure_matrix () {
  check_matrix_configuration

  configure_matrix
}

function check_and_configure_telegram () {
  check_telegram_configuration

  configure_telegram
}

function check_and_configure_sns () {
  check_sns_configuration

  configure_sns
}

function install_push_message_scripts() {
  local install_path="$1"
  get_script "$install_path" send-push-message run
  get_script "$install_path" send_sns.py run
  get_script "$install_path" send_matrix.py run
}

if [[ $EUID -ne 0 ]]
then
    log_progress "STOP: Run sudo -i."
    exit 1
fi

mkdir -p /root/bin

check_and_configure_pushover
check_and_configure_gotify
check_and_configure_ifttt
check_and_configure_discord
check_and_configure_webhook
check_and_configure_slack
check_and_configure_matrix
check_and_configure_telegram
check_and_configure_sns
install_push_message_scripts /root/bin

check_archive_configs

rm -f /root/teslausb.conf

archive_module="$( get_archive_module )"
log_progress "Using archive module: $archive_module"

install_archive_scripts /root/bin "$archive_module"
/tmp/verify-and-configure-archive.sh

systemctl disable teslausb.service || true

cat << EOF > /lib/systemd/system/teslausb.service
[Unit]
Description=TeslaUSB archiveloop service
DefaultDependencies=no
After=mutable.mount backingfiles.mount

[Service]
Type=simple
ExecStart=/bin/bash /root/bin/archiveloop
Restart=always

[Install]
WantedBy=backingfiles.mount
EOF

systemctl enable teslausb.service
