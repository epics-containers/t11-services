#!/bin/bash

# Group the files a 'copier update' touched by the team that owns them (from
# CODEOWNERS' sections), and mark each as 'conflict' (still has copier's
# '--conflict inline' markers) or 'merged'. Run this once, straight after
# committing the update, so its description can be pasted into the merge
# request and each team ticks off its own files.
#
# usage: ./update_checklist.sh <base>
#   <base>  the ref to diff against -- the branch the update was made from
#           before the update commit, e.g. 'main'.
#
# Only the CODEOWNERS pattern forms this repo's template generates are
# understood: a leading '/', a trailing '/' for "this directory and
# everything under it", and at most one '*' wildcard component (e.g.
# '/services/bl01c-*/'). A hand-edited CODEOWNERS using other glob forms
# (leading-slash-free patterns, '**', negation) will not match correctly --
# rewrite such a pattern in this simpler form, or expect its files to show up
# under "not in any CODEOWNERS section".

set -e

ROOT=$(realpath "$(dirname "${0}")")
base=${1:?"usage: $0 <base>"}

cd "${ROOT}"

CODEOWNERS=CODEOWNERS
if [[ ! -f "${CODEOWNERS}" ]]; then
    echo "ERROR: no CODEOWNERS file in ${ROOT}" >&2
    exit 1
fi

CHANGED=$(git diff --name-only "${base}" -- .)
if [[ -z "${CHANGED}" ]]; then
    echo "No files changed since ${base}"
    exit 0
fi

# Print every team that owns $1, one per line (nothing if none of CODEOWNERS'
# sections claim it). GitLab evaluates each section independently -- a file
# claimed by more than one section (see CODEOWNERS.jinja's header comment)
# is reported under every one of them. Within a single section, later
# patterns don't need to override earlier ones since GitLab CODEOWNERS has
# no negation: any matching pattern in a section is enough to claim the
# file for that section. On GitHub, section headers are themselves comments
# ('# [Controls]'), so the header check below runs before comment-stripping.
team_for() {
    local file="/$1" line section pattern matched=""
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace
        [[ -z "${line}" ]] && continue
        if [[ ${line} =~ ^(#\ ?)?\^?\[([^]]+)\] ]]; then
            section="${BASH_REMATCH[2]}"
            continue
        fi
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"  # trim again after comment-strip
        [[ -z "${line}" ]] && continue
        [[ -z "${section:-}" ]] && continue
        pattern=$(awk '{print $1}' <<<"${line}")
        [[ ${pattern:0:1} == "/" ]] || continue  # see header comment
        pattern="${pattern%/}"
        # unquoted: a '*' in pattern (e.g. '/services/bl13j-*') must still
        # glob-match here, not be taken as a literal asterisk
        case "${file}" in
            ${pattern} | ${pattern}/*)
                # record each distinct section once, in the order first matched
                [[ $'\n'"${matched}" == *$'\n'"${section}"$'\n'* ]] ||
                    matched+="${section}"$'\n'
                ;;
        esac
    done <"${CODEOWNERS}"
    printf '%s' "${matched}"
}

declare -A BY_TEAM
UNCLAIMED=()
while IFS= read -r file; do
    teams=$(team_for "${file}")
    if [[ -z "${teams}" ]]; then
        UNCLAIMED+=("${file}")
        continue
    fi
    if [[ -f "${file}" ]] && grep -aq '^<<<<<<<' "${file}"; then
        status="conflict"
    else
        status="merged"
    fi
    # a file can be claimed by more than one section -- record it under each
    while IFS= read -r team; do
        BY_TEAM["${team}"]+="  ${status}  ${file}"$'\n'
    done <<<"${teams}"
done <<<"${CHANGED}"

# sorted, one team name per line: a plain $(...) here would word-split a
# team name that contains a space (e.g. 'Data Acquisition')
if [[ ${#BY_TEAM[@]} -eq 0 ]]; then
    echo "No team-owned files changed"
else
    while IFS= read -r team; do
        echo "[${team}]"
        printf '%s' "${BY_TEAM[${team}]}" | sort
        echo
    done < <(printf '%s\n' "${!BY_TEAM[@]}" | sort)
fi

if [[ ${#UNCLAIMED[@]} -gt 0 ]]; then
    echo "Not in any CODEOWNERS section (expected layout: '[Controls]', '[Data Acquisition]' and '[Tech UI]' sections, as the template's CODEOWNERS.jinja generates):"
    printf '  %s\n' "${UNCLAIMED[@]}"
fi
