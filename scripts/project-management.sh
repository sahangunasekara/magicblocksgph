#!/bin/bash

# This script is used to help automate project management in GitHub
# It expects to be called in a GitHub actions workflow with the following setup
#
# EVENT = github.event
# GITHUB_TOKEN = secrets.GITHUB_TOKEN

# Configuration
#
# Here follows a bunch of magic numbers which correspond to IDs of the API
# objects we're insterested in.
LSP_PROJECT=11250171
LSP_BACKLOG=12653773
LSP_TODO=12653763
LSP_PROGRESS=12653764

VSCODE_PROJECT=11250281
VSCODE_BACKLOG=12653879
VSCODE_TODO=12653871
VSCODE_PROGRESS=12653872

PREVIEW_HEADER="application/vnd.github.inertia-preview+json"


add_to_project () {

    issue_id=$1
    label_name=$2

    column_id=""

    case "${label_name}" in
        lsp)
            column_id=$LSP_BACKLOG
            ;;
        vscode)
            column_id=$VSCODE_BACKLOG
            ;;
        *)
            echo "Unknown label '${label_name}', doing nothing"
            return
            ;;
    esac

    echo "Adding issue '${issue_id}' to column '${column_id}'"
    curl -s -X POST "https://api.github.com/projects/columns/${column_id}/cards" \
         -H "Accept: ${PREVIEW_HEADER}" \
         -H "Authorization: Bearer ${GITHUB_TOKEN}" \
         -H "Content-Type: application/json" \
         -d "{\"content_id\": ${issue_id}, \"content_type\": \"Issue\"}"
}


remove_from_project () {

    issue_number=$1
    label_name=$2

    case "${label_name}" in
        lsp)
            column_id=$LSP_BACKLOG
            ;;
        vscode)
            column_id=$VSCODE_BACKLOG
            ;;
        *)
            echo "Unknown label '${label_name}', doing nothing"
            return
            ;;
    esac

    # Need to look to see which card corresponds to the issue.
    echo "Looking for issue in column '${column_id}'"
    card_id=$(curl -s -X GET "https://api.github.com/projects/columns/${column_id}/cards" \
         -H "Accept: ${PREVIEW_HEADER}" \
         -H "Authorization: Bearer ${GITHUB_TOKEN}" | jq --arg issue "${issue_number}" -r '.[] | select(.content_url | test(".*/" + $issue)) | .id')

    if [ -z "${card_id}" ]; then
        echo "Couldn't find card for issue '${issue_number}', doing nothing"
        return
    fi

    echo "Removing card '${card_id}' from column '${column_id}'"
    curl -s -X DELETE "https://api.github.com/projects/columns/cards/${card_id}" \
         -H "Accept: ${PREVIEW_HEADER}" \
         -H "Authorization: Bearer ${GITHUB_TOKEN}"
}


card_in_progress () {

    issue_number=$1
    label_name=$2

    case "${label_name}" in
        lsp)
            new_column_id=$LSP_PROGRESS
            old_column_ids=($LSP_BACKLOG $LSP_TODO)
            ;;
        vscode)
            new_column_id=$VSCODE_PROGRESS
            old_column_ids=($VSCODE_BACKLOG $VSCODE_TODO)
            ;;
        *)
            echo "Unknown label '${label_name}', doing nothing"
            return
            ;;
    esac

    # Need to look to see which card corresponds to the issue
    for old_column_id in ${old_column_ids[@]}; do
        echo "Looking for issue in column '${old_column_id}'"
        card_id=$(curl -s -X GET "https://api.github.com/projects/columns/${old_column_id}/cards" \
                       -H "Accept: ${PREVIEW_HEADER}" \
                       -H "Authorization: Bearer ${GITHUB_TOKEN}" | jq --arg issue "${issue_number}" -r '.[] | select(.content_url | test(".*/" + $issue)) | .id')

        if [ -n "${card_id}" ]; then
            echo "Found card '${card_id}' in column '${old_column_id}'"
            break
        fi
    done

    if [ -z "${card_id}" ]; then
        echo "Couldn't find card for issue '${issue_number}', doing nothing"
        return
    fi

    echo "Moving card '${card_id}' to column '${new_column_id}'"
    curl -s -X POST "https://api.github.com/projects/columns/cards/${card_id}/moves" \
         -H "Accept: ${PREVIEW_HEADER}" \
         -H "Authorization: Bearer ${GITHUB_TOKEN}" \
         -H 'Content-Type: application/json' \
         -d "{\"column_id\": ${new_column_id}, \"position\": \"top\"}"
}


card_to_backlog () {

    issue_number=$1
    label_name=$2

    case "${label_name}" in
        lsp)
            new_column_id=$LSP_BACKLOG
            old_column_id=$LSP_PROGRESS
            ;;
        vscode)
            new_column_id=$VSCODE_BACKLOG
            old_column_id=$VSCODE_PROGRESS
            ;;
        *)
            echo "Unknown label '${label_name}', doing nothing"
            return
            ;;
    esac

    # Need to look to see which card corresponds to the issue
    echo "Looking for issue in column '${old_column_id}'"
    card_id=$(curl -s -X GET "https://api.github.com/projects/columns/${old_column_id}/cards" \
                   -H "Accept: ${PREVIEW_HEADER}" \
                   -H "Authorization: Bearer ${GITHUB_TOKEN}" | jq --arg issue "${issue_number}" -r '.[] | select(.content_url | test(".*/" + $issue)) | .id')

    if [ -z "${card_id}" ]; then
        echo "Couldn't find card for issue '${issue_number}', doing nothing"
        return
    fi

    echo "Moving card '${card_id}' to column '${new_column_id}'"
    curl -s -X POST "https://api.github.com/projects/columns/cards/${card_id}/moves" \
         -H "Accept: ${PREVIEW_HEADER}" \
         -H "Authorization: Bearer ${GITHUB_TOKEN}" \
         -H 'Content-Type: application/json' \
         -d "{\"column_id\": ${new_column_id}, \"position\": \"top\"}"
}

#
# Script start.
#


if [ -z "${GITHUB_TOKEN}" ]; then
   echo "Github token is not set."
   exit 1
fi

action=$(echo "${EVENT}" | jq -r .action)
label_name=$(echo "${EVENT}" | jq -r .label.name)
issue=$(echo "${EVENT}" | jq -r .issue.id )
issue_number=$(echo "${EVENT}" | jq -r .issue.number)

echo
echo "Action:       ${action}"
echo "Label:        ${label_name}"
echo "Issue Id:     ${issue}"
echo "Issue Number: ${issue_number}"
echo

case "$action" in
    assigned)
        echo
        echo "Looking for project label"
        label_name=$(echo "${EVENT}" | jq -r '.issue.labels[].name' | grep -E "lsp|vscode")
        echo "Label Name: ${label_name}"

        card_in_progress "${issue_number}" "${label_name}"
        ;;
    labeled)
        add_to_project "${issue}" "${label_name}"
        ;;
    unassigned)
        echo
        echo "Looking for project label"
        label_name=$(echo "${EVENT}" | jq -r '.issue.labels[].name' | grep -E "lsp|vscode")
        echo "Label Name: ${label_name}"

        card_to_backlog "${issue_number}" "${label_name}"
        ;;
    unlabeled)
        remove_from_project "${issue_number}" "${label_name}"
        ;;
    *)
        echo "Unknown action '${action}', doing nothing"
esac
