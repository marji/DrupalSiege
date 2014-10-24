#!/bin/bash

while getopts ":f:" OPT
do
  case $OPT in
    f ) URLFILE="$OPTARG" ;;
  esac
done

## prompt for drupal login. Comment this out and fill define DBUSER and DBPASS below to skip this step....
read -p "Drupal Login: " DUSER;
stty -echo 
read -p "Password: " DPASS;
stty echo
#DUSER=''
#DPASS=''

## url encode the password
DPASS=$(echo -n "${DPASS}" | perl -pe 's/([^-_.~A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg')

## create a temp file to hold the siegerc
SIEGERCFILE=$(mktemp /tmp/$(basename $0).XXXXXX) || exit 1

if [[ -n "$URLFILE" ]]
then
  RAWSITE="$(head -1 $URLFILE)"
  SITE="${RAWSITE#}"
else
  SITE="${!#}"
fi

LOGINURL=""

if [ "$SUBDIR_SITE" != "0" ]; then
  echo "Determining the BASE site URL by looking for install.php..."
  ## figure out the base site URL to contruct the URL for the login page
  ## remove trailing slash
  BASESITE=$(echo ${SITE%/})
  PRE_BASESITE=$BASESITE
  while true
  do
    SUB=$(echo ${BASESITE##*/})
    HTTPCODE=$(curl -s --output /dev/null -w "%{http_code}\n" ${BASESITE}/install.php)
    if [[ "${HTTPCODE}" == 200 ]]
    then
      LOGINURL="${BASESITE}/user"
      break
    fi
    BASESITE=$(echo ${BASESITE} | sed "s/\/${SUB}//")
    if [ "$BASESITE" == "$PRE_BASESITE" ]; then
      # We didn't find a base site using the intall.php method.
      echo "   ... not found."
      break
    fi
    PRE_BASESITE=$BASESITE
  done
fi

if [ -z "$LOGINURL" ]; then
  # We didn't find a base site using the intall.php method.
  # let's assume the site runs on the FQDN (not in a subdirectory):
  #
  echo "Assuming the BASE site URL = FQDN"
  # extract the protocol
  proto="$(echo $SITE | grep :// | sed -e's,^\(.*://\).*,\1,g')"
  # remove the protocol
  url="$(echo ${SITE/$proto/})"
  # remove everything from first slash (if any)
  fqdn=${url%%/*}
  # So the login url is:
  LOGINURL="${proto}${fqdn}/user"
fi
echo -n "Determined login URL: "
echo $LOGINURL

POSTVARS="name=${DUSER}&pass=${DPASS}&form_id=user_login&op=Log+in"

LOGFILE=$(siege -C | grep "log file" | awk -F: '{print $2}' | sed 's# ##g')
SIEGERC="$(siege -C | grep "resource file:" | awk -F: '{print $2}' | sed 's# ##g')"
SIEGELOGINURL="
login-url = ${LOGINURL} POST ${POSTVARS}
"

cat "${SIEGERC}" > ${SIEGERCFILE}
echo "${SIEGELOGINURL}" >> ${SIEGERCFILE}

echo "siege -R ${SIEGERCFILE} $@"
siege -R ${SIEGERCFILE} $@

rm ${SIEGERCFILE}
