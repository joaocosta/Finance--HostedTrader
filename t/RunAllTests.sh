#!/bin/sh

set -e

while getopts ":c" opt; do
    case $opt in
      c)
         USE_COVER=1
         ;;
    esac
done

if [ $USE_COVER ]; then
    export HARNESS_PERL_SWITCHES="-MDevel::Cover=+ignore,.t$"
    cover -delete
fi
prove -r --timer .
if [ $USE_COVER ]; then
    cover
    chmod 775 cover_db
fi