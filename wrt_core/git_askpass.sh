#!/usr/bin/env bash

case "$1" in
    *Username*)
        printf '%s\n' 'x-access-token'
        ;;
    *Password*)
        printf '%s\n' "${GH_REPO_TOKEN:?GH_REPO_TOKEN is required for private GitHub repositories}"
        ;;
    *)
        exit 1
        ;;
esac
