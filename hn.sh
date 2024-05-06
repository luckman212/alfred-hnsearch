#!/usr/bin/env bash
#shellcheck disable=SC2154

# https://hn.algolia.com/api
# https://hn.algolia.com/help
# https://github.com/HackerNews/API
# item: https://hacker-news.firebaseio.com/v0/item/{ITEM}.json

# icon: https://www.pixelresort.com/project/hackernews
# see also: https://github.com/vitorgalvao/hackerboard-workflow

_inAlfred() {
	[[ -n $alfred_workflow_uid ]]
}

_spidAlive() {
	[[ $(ps -ocommand= -p "$spid") == "bash $0 --search" ]]
}

_urlenc() {
	python3 -c 'import sys; from urllib.parse import quote,unquote; print(quote(unquote(sys.argv[1])));' "$1"
}

_arg() {
	(( $# > 0 )) || return 1
	for a; do
		[[ -n $a && $a != -* ]] || return 1
	done
	return 0
}

_usage() { cat <<-EOF
	$V_USAGESTR
	EOF
}

#ensure brew exists
if ! hash brew ; then
	cat <<-EOJ
	{
		"items": [{
			"title": "Homebrew is not installed!",
			"subtitle": "visit https://brew.sh for help installing Homebrew",
			"valid": false,
			"icon": { "path": "icons/brew.png" }
		}]
	}
	EOJ
	exit 1
fi

#ensure dependencies are installed
for f in fzf jq sponge:moreutils ; do
	hash ${f%%:*} &>/dev/null && continue
	if ! brew install --quiet ${f##*:} &>/dev/null ; then
		cat <<-EOJ
		{
			"items": [{
				"title": "${f%%:*} is required, but is not installed",
				"subtitle": "Try running brew install ${f##*:} in a Terminal to troubleshoot",
				"valid": false,
				"icon": { "path": "icons/brew.png" }
			}]
		}
	EOJ
	exit 1
	fi
done

#populate variables from Alfred workflow
if ! _inAlfred ; then
	this=$(/bin/realpath "$0")
	wf_dir=$(/usr/bin/dirname "$this")
	infoplist="${wf_dir}/info.plist"
	prefsplist="${wf_dir}/prefs.plist"
	DEFAULT_CONFIG=$(/usr/bin/plutil -extract userconfigurationconfig json -o - -- "$infoplist")
	USER_CONFIG=$(/usr/bin/plutil -convert json -o - -- "$prefsplist")
	wf_bundleid=$(plutil -extract bundleid raw -o - -- "$infoplist")
	export alfred_workflow_cache="$HOME/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data/$wf_bundleid"
	declare -ga WF_VARS
	while read -r VAR ; do
		WF_VARS+=( "$VAR" )
	done < <(jq -r '.[].variable' <<< "$DEFAULT_CONFIG")
	for v in "${WF_VARS[@]}"; do
		val=$(jq -r --arg v "$v" '.[$v] // empty' <<< "$USER_CONFIG") #check prefs first
		if [[ -z $val ]]; then #fall back to defaults
			val=$(jq -r --arg v "$v" '
				map(select(.variable==$v))[] | .config |
				first(.default, .defaultvalue | select(. != null))' <<< "$DEFAULT_CONFIG")
		fi
		declare -x "$v"="$val"
		#echo "$v = ${!v}"
	done
fi

API='https://hn.algolia.com/api/v1'
DOCS='https://hn.algolia.com/api'
HN_BASEURL='https://news.ycombinator.com'
HN_URL="$HN_BASEURL/item"
RESULTS_JSON=${json_out:-/tmp/results.json}
VERB=${VERB:-search_by_date}
BROWSE=true

if _inAlfred && [[ -z $runid ]]; then
	runid=$$
	rm 2>/dev/null "$RESULTS_JSON" "$SCRIPT_FILTER_JSON" "$JQ_ERRORS"
fi

#shellcheck disable=SC2034
V_USAGESTR="
Query Hacker News — $HN_BASEURL
  via Algolia API — $DOCS

usage: ${0##*/} [opts] [title]
    -p,--popularity    sort by points (if omitted, sort by date)
    -t,--type <type>   type: story (default), comment, show_hn, ask_hn - see docs
    -m,--min <pts>     minimum points (default: $HNS_POINTS)
    -u,--user <user>   search by username aka author
    -x,--hits <hits>   max results (default: $HNS_MAX_HITS)
    -n,--no-browse     don't open in browser
    -y,--allow-typos   fuzzy matching on misspelled words
    -r,--url           restrict matching to URL
    --nohistory        do not save search to history
    --lib [args]       perform action using hnlib Python library

    selected items will be:
      - output to the screen
      - opened in browser (unless -n flag is passed)
      - copied to the pasteboard in Markdown format

    tip: perform multi-word searches by quoting, exclude words with \`-\` e.g.
      ${0##*/} 'Microsoft acquire -Blizzard'
"

no_results() {
	cat <<-EOJ
	{
		"items": [{
			"title": "No results!",
			"subtitle": "Try again later, or modify your search query (↵ retry)",
			"arg": "",
			"valid": true,
			"variables": {
				"HNS_ACTION": "retry",
				"completed": 0,
				"search_desc": "$s"
			},
			"icon": { "path": "icons/gray.png" }
		}]
	}
	EOJ
}

alfredSpinner() {
	c=${loopcount:-0}
	st=${st:-$EPOCHSECONDS}
	et=$(( EPOCHSECONDS - st ))
	rsize=$(jq 'length' "$RESULTS_JSON" 2>/dev/null)
	i="spinner$(( c % 6 )).png" #set to number of icons + 1
	_spidAlive && sstat="🟢" || sstat="🔴"
	if (( et > HNS_MAX_TIME )); then
		echo 1>&2 "Timeout (${HNS_MAX_TIME}s) exceeded"
		_spidAlive && kill "$spid"
		no_results
		exit
	else
		cat <<-EOJ
		{
			"rerun": ${HNS_SPINNER_REFRESH:-0.5},
			"variables": {
				"loopcount": $(( c+1 )),
				"st": $st,
				"spid": ${spid:-null},
				"runid": $runid,
				"HNS_ACTION": "$HNS_ACTION"
			},
			"items": [{
				"title": "$HNS_SPINNER_MSG",
				"subtitle": "${rsize:-0} results for ${search_desc}, thread: $sstat",
				"valid": false,
				"icon": { "path": "icons/$i" }
			}]
		}
		EOJ
		exit
	fi
}

_doSearch() {
	RESULT_SIZE=0
	echo '[]' >"$RESULTS_JSON"
	while true; do # [[ $hasNextPage != false ]]
		res=$(_fetch)
		[[ $DEBUG == true ]] && jq <<<"$res"
		HITS=$(jq -r <<<"$res" '.nbHits')
		#echo "total hits: $HITS"
		#echo "$(jq -r <<<"$res" '.nbPages') pages with $HNS_PAGESIZE items each"
		(( HITS > 0 )) || break
		jq \
			--null-input \
			--argjson r "$res" \
			--slurpfile cur "$RESULTS_JSON" '[ $cur[0], $r.hits ] | add' |
		sponge "$RESULTS_JSON"
		PAGE=$(jq -r <<<"$res" '.page + 1')
		NUM_PAGES=$(jq -r <<<"$res" '.nbPages')
		RESULT_SIZE=$(jq 'length' "$RESULTS_JSON")
		if ! _inAlfred; then
			_spinner 3 "${PAGE:-0}" "${RESULT_SIZE:-0}"
		fi
		#sleep 0.1
		(( RESULT_SIZE >= HNS_MAX_HITS )) && break
		(( PAGE >= NUM_PAGES )) && break
	done
}

searchAndGenerateAlfredResultsJson() {
	_doSearch
	if (( RESULT_SIZE == 0 )); then
		no_results >"${SCRIPT_FILTER_JSON}"
	else
		jq \
		--arg v "$VERB" \
		--arg s "$search_desc" \
		--arg h "$VERB|$search|$AUTHOR|$HNS_POINTS" \
		--argjson x "$HNS_MAX_HITS" \
		--arg hnu "${HN_URL}?id" \
		--arg ua "$HNS_URL_ACTION" '
		.[:$x] // empty |
		if $v=="search" then sort_by(-.points) else . end |
		map(
			.date = .created_at[:10] |
			.comments_url = ([ $hnu, .story_id ] | join("=")) |
			if $ua == "comments" then
				.urls = [ .comments_url, .url ]
			else
				.urls = [ .url, .comments_url ]
			end |
			.first_url = (.urls[0] // .urls[1]) |
			{
				title: .title,
				arg: .first_url,
				quicklookurl: .first_url,
				match: ([ .title, .author, .date, (.url // "") ] | join(" ")),
				subtitle: ("↑" + (.points|tostring) + "   " + .author + "   " + .date),
				mods: {
					ctrl: {
						arg: ("[" + .title + "](" + .first_url + ")"),
						variables: { "HNS_ACTION": "copy" },
						subtitle: "↵ copy as Markdown"
					},
					cmd: { arg: .urls[0], subtitle: .urls[0] },
					alt: { arg: .urls[1], subtitle: .urls[1] }
				}
			}) as $items |
			{
				skipknowledge: true,
				items: $items,
				variables: {
					completed: ( now | floor ),
					search_desc: $s,
					search_hash: $h
				}
			}' "$RESULTS_JSON" 2>"$JQ_ERRORS" >"$SCRIPT_FILTER_JSON"
		./hnlib.py \
			--action add \
			--search_desc "$search_desc" \
			--verb "$VERB" \
			--search "$search" \
			--author "$AUTHOR" \
			--points "$HNS_POINTS" \
			--search_hash "$search_hash"
	fi
}

_spawnSearchJob() {
	[[ -n $spid ]] && return
	nohup -- "$0" --search >/dev/null 2>&1 &
	spid=$!
	disown $spid
	[[ -n $spid ]] || { echo 1>&2 "background task was not started successfully"; exit 1; }
}

_fetch() {
	if _inAlfred ; then
		cat <<-EOF >"$alfred_workflow_cache/last_search.txt"
		query=$TITLE
		tags=${SECTION:-story}${AUTHOR:+,author_$AUTHOR}
		hitsPerPage=$HNS_PAGESIZE
		typoTolerance=${TYPOS:-false}
		page=${PAGE:-0}
		${ADDITIONAL_DATA[@]}
		$API/$VERB
		hash=$search_hash
		EOF
	fi
	[[ $DEBUG == true ]] && set -x
	curl 2>/dev/null \
	--silent \
	--location \
	--get \
	--request GET \
	--max-time 10 \
	--data "query=$TITLE" \
	--data "tags=${SECTION:-story}${AUTHOR:+,author_$AUTHOR}" \
	--data "hitsPerPage=$HNS_PAGESIZE" \
	--data "typoTolerance=${TYPOS:-false}" \
	--data "page=${PAGE:-0}" \
	"${ADDITIONAL_DATA[@]}" \
	"$API/$VERB"
}

if ! _inAlfred ; then
	#shellcheck disable=SC2086
	while true; do
		case $1 in
			-h|--help) _usage; exit;;
			-p|--popularity) VERB='search';;
			-t|--type) _arg "$2" && { SECTION=$2; shift; } || echo 1>&2 "$1 requires an argument";;
			-m|--min) _arg "$2" && { HNS_POINTS=$2; shift; } || echo 1>&2 "$1 requires an argument";;
			-u|--user) _arg "$2" && { AUTHOR=$2; shift; } || echo 1>&2 "$1 requires an argument";;
			-x|--hits) _arg "$2" && { HNS_MAX_HITS=$2; shift; } || echo 1>&2 "$1 requires an argument";;
			-n|--no-browse) BROWSE=false;;
			-y|--allow-typos) TYPOS=true;;
			-r|--url) RESTRICT='url';;
			--nohistory) export HNS_HIST_SIZE=0;;
			--lib) shift; "$wf_dir/hnlib.py" "$@"; exit;;
			--) shift;;
			-*) echo 1>&2 "skipping invalid arg: $1";;
			*) [[ -z $LAST_ARG ]] && LAST_ARG=$1;;
		esac
		(( $# )) && shift
		(( $# == 0 )) && break
	done
	CLI_SEARCH_DESC=$LAST_ARG
	#[[ -z $LAST_ARG && -z $AUTHOR ]] && { echo "you must specify a query or an author"; exit 1; }
fi

TITLE=$(_urlenc "${LAST_ARG:-$search}")

case $SECTION in
	comment)
		c3_header="author"
		c3_width=15
		;;
	*)
		c3_header="↑"
		c3_width=5
		ADDITIONAL_DATA+=( --data "numericFilters=points>=${HNS_POINTS}" )
		if [[ -n $TITLE ]]; then
			ADDITIONAL_DATA+=( --data "restrictSearchableAttributes=${RESTRICT:-title}" )
		fi
		;;
esac

if _inAlfred ; then
	if [[ ! -d $alfred_workflow_cache ]]; then
		mkdir -p "$alfred_workflow_cache"
	fi
	case $1 in
		spin)
			if ! _spidAlive && [[ -e $SCRIPT_FILTER_JSON ]]; then
				rsize=$(jq 'length' "$RESULTS_JSON" 2>/dev/null)
				if (( rsize > 0 )); then
					cat "$SCRIPT_FILTER_JSON"
				else
					no_results
				fi
				exit
			fi
			;;
		init)
			[[ -z $spid ]] && _spawnSearchJob
			HNS_ACTION='spin'
			;;
		--search)
			searchAndGenerateAlfredResultsJson
			exit
			;;
		*) echo 1>&2 "unexpected action! arg: $1"; exit 1;;
	esac
	alfredSpinner
else
	_doSearch
	(( RESULT_SIZE > 0 )) || { echo "no results"; exit 1; }
	printf '\r%*s\r' 10 ""
	if (( HNS_HIST_SIZE > 0 )); then #save to history
		"$wf_dir/hnlib.py" \
			--action add \
			--search_desc "$CLI_SEARCH_DESC" \
			--verb "$VERB" \
			--search "$CLI_SEARCH_DESC" \
			--author "$AUTHOR" \
			--points "$HNS_POINTS" \
			--search_hash "$VERB|$CLI_SEARCH_DESC|$AUTHOR|$HNS_POINTS"
	fi
	#separate arrays because iterating over associative arrays in Bash is non-deterministic
	declare -A TITLES
	declare -a IDS
	printf -v FZF_HEADER "%-10s\t%-10s\t%-${c3_width}s\t%s" "ID" "Date" "${c3_header}" "Title"
	while IFS=$'\t' read -u3 -r ID _ _ TITLE _ ; do
		ID=${ID// } #trim spaces
		IDS+=( "$ID" )
		TITLES[$ID]="$TITLE"
	done 3< <(
		jq \
		--raw-output \
		--arg v "$VERB" \
		--arg t "$SECTION" \
		--argjson w "$c3_width" \
		--argjson x "$HNS_MAX_HITS" \
		'def rpad($len): tostring | ($len - length) as $l | . + (" " * $l)[:$l];
		.[:$x] // empty |
		if $v=="search" then sort_by(-.points) else . end | .[] |
		if $t=="comment" then
			[ (.objectID|rpad(8)), .created_at[:10], (.author[:$w]|rpad($w)), .story_title, .url ]
		else
			[ (.story_id|rpad(8)), .created_at[:10], (.points|tostring|rpad($w)), .title, .url ]
		end | @tsv' \
		"$RESULTS_JSON" |
		fzf \
			--header="$FZF_HEADER" \
			--border=none \
			--multi \
			--exact \
			--no-select-1 \
			--exit-0 \
			--no-hscroll \
			--delimiter='\t' \
			--with-nth=1,2,3,4 \
			--preview-window='bottom,20%,wrap' \
			--bind 'ctrl-p:change-preview-window(40%|)' \
			--preview 'echo {4} - {5}')
	c=0
	for item in "${IDS[@]}"; do
		(( c > 0 )) && sleep 1.1 #avoid being blocked by pages opening too rapidly
		URL="${HN_URL}?id=${item}"
		echo "$URL - ${TITLES[$item]}"
		if [[ $BROWSE == true ]]; then
			open "$URL"
		fi
	done
	#copy markdown-formatted results to pasteboard
	for item in "${IDS[@]}"; do
		echo "- [${TITLES[$item]}](${HN_URL}?id=${item})"
	done | pbcopy
fi
