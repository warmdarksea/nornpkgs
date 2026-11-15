_gensokyo_agent() {
  local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}
  case $prev in
    -c|--connection)
      mapfile -t COMPREPLY < <(compgen -W "$(podman system connection ls --format '{{.Name}}' 2>/dev/null)" -- "$cur")
      return ;;
    --model)
      mapfile -t COMPREPLY < <(compgen -W "fable opus sonnet haiku opusplan" -- "$cur")
      return ;;
    --effort)
      mapfile -t COMPREPLY < <(compgen -W "low medium high xhigh max" -- "$cur")
      return ;;
  esac
  if [[ $cur == -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W "--legacy --name --connection --secret --gpu --vm --no-vm --device --git --cp --ro --rw --bind --prompt --model --effort --publish -L -sp --help" -- "$cur")
  fi
}
# paths are the default: most of the other flags start with one
complete -o default -F _gensokyo_agent gensokyo-agent
