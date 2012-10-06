#!/bin/bash
trap '' INT KILL

# don't run as operators 
if ! groups | grep -q vyattacfg; then
  exit 0
fi

# don't run if we've already done this, 
# the commit system will handle the invalid password
if [ -e /opt/vyatta/etc/.nofirstpasswd ]; then
  exit 0
fi

# don't run on livecd installer will do the check
if grep -q -e '^unionfs.*/filesystem.squashfs' /proc/mounts; then
  exit 0
fi

configdiff=$(cli-shell-api showConfig --show-cfg1 @ACTIVE --show-cfg2 /config/config.boot --show-context-diff)

API=/bin/cli-shell-api

session_env=$($API getSessionEnv $PPID)
eval $session_env
$API setupSession

exit_configure ()
{
  $API teardownSession
  echo -n 'export -n VYATTA_CONFIG_TMP; '
  echo -n 'export -n VYATTA_CHANGES_ONLY_DIR; '
  echo -n 'export -n VYATTA_ACTIVE_CONFIGURATION_DIR; '
  echo -n 'export -n VYATTA_TEMPLATE_LEVEL; '
  echo -n 'export -n VYATTA_CONFIG_TEMPLATE; '
  echo -n 'export -n VYATTA_TEMP_CONFIG_DIR; '
  echo -n 'export -n VYATTA_EDIT_LEVEL; '
}

set ()
{
  /opt/vyatta/sbin/my_set $*
}

commit ()
{
  /opt/vyatta/sbin/my_commit "$@"
}

save ()
{
  # do this the same way that vyatta-cfg does it
  local save_cmd=/opt/vyatta/sbin/vyatta-save-config.pl
  eval "sudo sg vyattacfg \"umask 0002 ; $save_cmd\""
}

show ()
{
  $API showCfg "$@"
}

change_password() {
  local user=$1
  local pwd1="1"
  local pwd2="2"

  echo "Invalid password detected for user $user"
  echo "Please enter a new password"
  until [[ "$pwd1" == "$pwd2" && "$pwd1" != "vyatta" ]]; do
    read -p "Enter $user password:" -r -s pwd1 <>/dev/tty 2>&0
    echo
    if [[ "$pwd1" == "" ]]; then
      echo "'' is not a valid password"
      continue
    fi
    read -p "Retype $user password:" -r -s pwd2 <>/dev/tty 2>&0
    echo

    if [[ "$pwd1" != "$pwd2" ]]; then 
      echo "Passwords do not match"
      continue
    fi
    if [[ "$pwd1" == "vyatta" ]]; then
      echo "'vyatta' is not a vaild password"
      continue
    fi 
  done

  # escape any slashes in resulting password
  local epwd=$(mkpasswd -H md5 "$pwd1" | sed 's:/:\\/:g')
  set system login user $user authentication plaintext-password "$pwd1"
}

dpwd='"*"'
for user in $($API listEffectiveNodes system login user); do
  user=${user//\'/}
  epwd=$(show system login user $user authentication encrypted-password)
  epwd=$(awk '{ print $2 }' <<<$epwd)
  # check for old unsalted default password string.
  if [[ $epwd == '$1$$Ht7gBYnxI1xCdO/JOnodh.' ]]; then
     change_password $user
     continue
  fi
  if [[ $epwd != $dpwd ]]; then
    salt=$(awk 'BEGIN{ FS="$" }; { print $3 }' <<<$epwd)
    if [[ $salt == '' ]];then
      continue
    fi
    vyatta_epwd=$(mkpasswd -H md5 -S $salt vyatta)
    if [[ $epwd == $vyatta_epwd ]]; then
       change_password $user
    fi
  fi
done

if $API sessionChanged; then
  commit
  if [[ -z $configdiff ]] ; then
    save
  else
    echo "Warning: potential configuration issues exist." 
    echo "User passwords have been updated but the configuration has not been saved." 
    echo "Please review and validate the running configuration before saving."
  fi
fi
eval $(exit_configure)
sudo touch /opt/vyatta/etc/.nofirstpasswd
