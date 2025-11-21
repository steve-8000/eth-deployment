#!/usr/bin/env bash

KEYSTORE_DIR=".key/validator_keys"
VC_PASSWORD_FILENAME="password.txt"

for f in $KEYSTORE_DIR/keystore-*.json; do
  echo "Checking password file of ${f}"

  password_file="${f//json/txt}"
  
  if [ -e "${KEYSTORE_DIR}/${VC_PASSWORD_FILENAME}" ]; then

    if [ ! -e "${password_file}" ]; then
      cp $KEYSTORE_DIR/${VC_PASSWORD_FILENAME} ${password_file}
      echo "Copying password file ${password_file}"
    else
      echo "File already exists ${password_file}. Ignoring..."
    fi

  else
    echo "${VC_PASSWORD_FILENAME} file not found. Skipping..."
  fi
done