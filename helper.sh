#!/usr/bin/env bash
#shellcheck disable=SC2154

case $HNS_ACTION in
	clear_cache)
		mkdir -p "${alfred_workflow_cache}"
		if find "${alfred_workflow_cache:?}" -type f -delete >/dev/null ; then
			cat <<-EOJ
			{
				"items": [
					{
						"title": "Cache has been cleared!",
						"subtitle": "press ↵ to restart workflow",
						"icon": { "path": "icons/trash.png" }
					}
				]
			}
			EOJ
			exit 0
		fi
		;;
	install_cli)
		if ln -sf "$PWD/hn.sh" "$HNS_CLI_FQPN" &>/dev/null ; then
			cat <<-EOJ
			{
				"items": [
					{
						"title": "Commandline tool installed → ${HNS_CLI_FQPN}",
						"subtitle": "press ↵ to restart workflow",
						"icon": { "path": "icons/cli.png" }
					}
				]
			}
			EOJ
			exit 0
		fi
		;;
esac

cat <<EOJ
{
  "items": [
    {
      "title": "Something went wrong!",
      "subtitle": "Check the Debugger output for more detail",
      "icon": { "path": "icons/gray.png" },
      "valid": "false"
    }
  ]
}
EOJ
