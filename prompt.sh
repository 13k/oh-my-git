#!/bin/bash

[[ -z "$BASH_VERSION" ]] && return 0

readonly OMG_GIT_CONFIG_KEY="oh-my-git.enabled"
readonly OMG_MARK="omg_prompt_mark"
readonly OMG_ESC_MARK="\\e_${OMG_MARK}\\e\\\\"
readonly OMG_ORIGINAL_PS1="$PS1"

# config
: "${omg_separator_symbol:=""}"
: "${omg_terminator_symbol:="$omg_separator_symbol"}"
: "${omg_is_a_git_repo_symbol:=""}"
: "${omg_has_untracked_files_symbol:=""}"
: "${omg_has_adds_symbol:=""}"
: "${omg_has_deletions_symbol:=""}"
: "${omg_has_cached_deletions_symbol:=""}"
: "${omg_has_cached_modifications_symbol:=""}"
: "${omg_has_modifications_symbol:=""}"
: "${omg_ready_to_commit_symbol:=""}"
: "${omg_is_on_a_tag_symbol:=""}"
: "${omg_needs_to_merge_symbol:=""}"
: "${omg_detached_symbol:=""}"
: "${omg_can_fast_forward_symbol:=""}"
: "${omg_has_diverged_symbol:=""}"
: "${omg_not_tracked_branch_symbol:=""}"
: "${omg_rebase_tracking_branch_symbol:=""}"
: "${omg_merge_tracking_branch_symbol:=""}"
: "${omg_should_push_symbol:=""}"
: "${omg_has_stashes_symbol:=""}"

: "${omg_primary_color:="red"}"
: "${omg_secondary_color:="white"}"
: "${omg_terminator_color:="red:default"}"

readonly -A omg_color_table_hl=(
  [reset]=0
  [bold]=1
  [dim]=2
  [standout]=3
  [underline]=4
)

readonly -A omg_color_table_fg=(
  [black]=30
  [red]=31
  [green]=32
  [yellow]=33
  [blue]=34
  [magenta]=35
  [cyan]=36
  [white]=37
)

readonly -A omg_color_table_bg=(
  [black]=40
  [red]=41
  [green]=42
  [yellow]=43
  [blue]=44
  [magenta]=45
  [cyan]=46
  [white]=47
  [default]=49
)

function omg_expand_color() {
  if [[ "$1" == *'\e['* ]]; then
    # assumes it's already expanded
    echo -n "$1"
    return 0
  fi

  local -a color_names
  local -a color_codes
  local color_idx color_name color_code

  readarray -d ':' -t color_names < <(echo -n "$1")

  for color_idx in "${!color_names[@]}"; do
    if [[ $color_idx -eq 0 ]]; then
      local -n color_table="omg_color_table_fg"
    elif [[ $color_idx -eq 1 ]]; then
      local -n color_table="omg_color_table_bg"
    else
      local -n color_table="omg_color_table_hl"
    fi

    color_name="${color_names[$color_idx]}"
    color_code="${color_table[$color_name]}"

    if [[ -z "$color_code" && $color_idx -eq 0 ]]; then
      local -n color_table="omg_color_table_hl"
      color_code="${color_table[$color_name]}"
    fi

    if [[ -z "$color_code" ]]; then
      echo >&2 "${BASH_SOURCE[0]}: Invalid color '$color_name' (color table: ${!color_table})"
      return 1
    fi

    color_codes=("${color_codes[@]}" "$color_code")
  done

  local color_codes_join
  color_codes_join="$(IFS=';'; echo "${color_codes[*]}")"

  echo -n "\\[\\e[${color_codes_join}m\\]"
}

omg_setpp_local_inactive="$(omg_expand_color "black:$omg_secondary_color")"
omg_setpp_local_active="$(omg_expand_color "$omg_primary_color:$omg_secondary_color")"
omg_setpp_remote_inactive="$(omg_expand_color "black:$omg_primary_color")"
omg_setpp_remote_active="$(omg_expand_color "$omg_secondary_color:$omg_primary_color")"

omg_termination="$(omg_expand_color "$omg_terminator_color")"
omg_termination+="${omg_terminator_symbol}"
omg_termination+="$(omg_expand_color "reset")"

function omg_callback_defined() {
  declare -fF "$1" &> /dev/null
}

function omg_eval_prompt_callback() {
  local callback_name="omg_prompt_callback"
  [[ -n "$1" ]] && callback_name+="_$1"
  omg_callback_defined "$callback_name" && "$callback_name"
}

function omg_enrich_append() {
  local flag="$1"
  local symbol="$2"
  local color="$3"
  [[ $flag == false ]] && symbol=' '
  echo -n "${color}${symbol}  "
}

function omg_detect_state() {
  local enabled="$OMG_PROMPT_ENABLED"

  if [[ -z "$enabled" ]]; then
    enabled="$(git config --get "$OMG_GIT_CONFIG_KEY" 2>/dev/null)"
  fi

  [[ $enabled == false ]] && return 1

  # declare the nameref with a prefix to avoid circular references (s -> s)
  local -n _s="$1"

  _s[is_git_repo]=false
  _s[current_commit_hash]=""
  _s[current_branch]=""
  _s[is_detached]=false
  _s[just_init]=false
  _s[upstream]=""
  _s[has_upstream]=false
  _s[has_modifications]=false
  _s[has_modifications_cached]=false
  _s[has_adds]=false
  _s[has_deletions]=false
  _s[has_deletions_cached]=false
  _s[has_untracked_files]=false
  _s[ready_to_commit]=false
  _s[tag_at_current_commit]=""
  _s[is_on_a_tag]=false
  _s[has_upstream]=false
  _s[commits_ahead]=0
  _s[commits_behind]=0
  _s[has_diverged]=false
  _s[should_push]=false
  _s[will_rebase]=false
  _s[has_stashes]=false

  _s[current_commit_hash]="$(git rev-parse HEAD 2> /dev/null)"
  [[ -n "${_s[current_commit_hash]}" ]] && _s[is_git_repo]=true

  if [[ ${_s[is_git_repo]} == true ]]; then
    _s[current_branch]="$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"
    [[ "${_s[current_branch]}" == "HEAD" ]] && _s[is_detached]=true

    local number_of_logs
    number_of_logs="$(git log --pretty=oneline -n1 2> /dev/null | wc -l)"

    if [[ $number_of_logs -eq 0 ]]; then
      _s[just_init]=true
    else
      _s[upstream]="$(git rev-parse --symbolic-full-name --abbrev-ref "@{upstream}" 2> /dev/null)"
      [[ -n "${_s[upstream]}" && "${_s[upstream]}" != "@{upstream}" ]] && _s[has_upstream]=true

      local git_status
      git_status="$(git status --porcelain 2> /dev/null)"

      [[ "$git_status" =~ ($'\n'|^).M ]] && _s[has_modifications]=true
      [[ "$git_status" =~ ($'\n'|^)M ]] && _s[has_modifications_cached]=true
      [[ "$git_status" =~ ($'\n'|^)A ]] && _s[has_adds]=true
      [[ "$git_status" =~ ($'\n'|^).D ]] && _s[has_deletions]=true
      [[ "$git_status" =~ ($'\n'|^)D ]] && _s[has_deletions_cached]=true
      [[ "$git_status" =~ ($'\n'|^)[MAD] && ! "$git_status" =~ ($'\n'|^).[MAD\?] ]] \
        && _s[ready_to_commit]=true

      local number_of_untracked_files
      number_of_untracked_files="$(\grep -c "^??" <<< "${git_status}")"

      [[ $number_of_untracked_files -gt 0 ]] && _s[has_untracked_files]=true

      _s[tag_at_current_commit]="$(
        git describe --exact-match --tags \
          "${_s[current_commit_hash]}" 2> /dev/null
      )"

      [[ -n "${_s[tag_at_current_commit]}" ]] && _s[is_on_a_tag]=true

      local commits_diff
      if [[ ${_s[has_upstream]} == true ]]; then
        commits_diff="$(
          git log --pretty=oneline --topo-order --left-right \
          "${_s[current_commit_hash]}...${_s[upstream]}" 2> /dev/null
        )"

        _s[commits_ahead]="$(\grep -c "^<" <<< "$commits_diff")"
        _s[commits_behind]="$(\grep -c "^>" <<< "$commits_diff")"
      fi

      [[ ${_s[commits_ahead]} -gt 0 && ${_s[commits_behind]} -gt 0 ]] && _s[has_diverged]=true
      [[ ${_s[has_diverged]} == false && ${_s[commits_ahead]} -gt 0 ]] && _s[should_push]=true

      local number_of_stashes
      _s[will_rebase]="$(git config --get "branch.${_s[current_branch]}.rebase" 2> /dev/null)"
      number_of_stashes="$(git stash list -n1 2> /dev/null | wc -l)"
      [[ $number_of_stashes -gt 0 ]] && _s[has_stashes]=true
    fi
  fi

  return 0
}

function omg_previous_prompt() {
  if [[ "$PS1" == *${OMG_MARK}* ]]; then
    echo "$OMG_ORIGINAL_PS1"
  else
    echo "$PS1"
  fi
}

function omg_build_prompt() {
  local prev_prompt
  prev_prompt="$(omg_previous_prompt)" || return $?

  local -A s

  if ! omg_detect_state s; then
    echo "$prev_prompt"
    return 0
  fi

  local prompt="\\[$OMG_ESC_MARK\\]"

  if [[ "${s[is_git_repo]}" == true ]]; then

    prompt+="$(omg_eval_prompt_callback before_first)"

    # local --------------

    prompt+="${omg_setpp_local_inactive} "
    prompt+="$(omg_enrich_append "${s[is_git_repo]}" "$omg_is_a_git_repo_symbol" "$omg_setpp_local_inactive")"
    prompt+="$(omg_enrich_append "${s[has_stashes]}" "$omg_has_stashes_symbol" "$omg_setpp_local_active")"
    prompt+="$(omg_enrich_append "${s[has_untracked_files]}" "$omg_has_untracked_files_symbol" "$omg_setpp_local_active")"
    prompt+="$(omg_enrich_append "${s[has_modifications]}" "$omg_has_modifications_symbol" "$omg_setpp_local_active")"
    prompt+="$(omg_enrich_append "${s[has_deletions]}" "$omg_has_deletions_symbol" "$omg_setpp_local_active")"
    prompt+="$(omg_enrich_append "${s[has_adds]}" "$omg_has_adds_symbol" "$omg_setpp_local_inactive")"
    prompt+="$(omg_enrich_append "${s[has_modifications_cached]}" "$omg_has_cached_modifications_symbol" "$omg_setpp_local_inactive")"
    prompt+="$(omg_enrich_append "${s[has_deletions_cached]}" "$omg_has_cached_deletions_symbol" "$omg_setpp_local_inactive")"
    prompt+="$(omg_enrich_append "${s[ready_to_commit]}" "$omg_ready_to_commit_symbol" "$omg_setpp_local_active")"

    # remote --------------

    prompt+=" $(omg_expand_color "reset")"
    prompt+="${omg_setpp_remote_active}${omg_separator_symbol} $omg_setpp_remote_inactive"

    if [[ "${s[is_detached]}" == true ]]; then
      prompt+="$(omg_enrich_append true "$omg_detached_symbol" "$omg_setpp_remote_active")"
      prompt+="$(omg_enrich_append true "(${s[current_commit_hash]:0:7})" "$omg_setpp_remote_inactive")"
    else
      if [[ "${s[has_upstream]}" == false ]]; then
        prompt+="$(omg_enrich_append true "-- ${omg_not_tracked_branch_symbol}  --  (${s[current_branch]})" "${omg_setpp_remote_inactive}")"
      else
        local type_of_upstream

        if [[ "${s[will_rebase]}" == true ]]; then
          type_of_upstream="$omg_rebase_tracking_branch_symbol"
        else
          type_of_upstream="$omg_merge_tracking_branch_symbol"
        fi

        if [[ "${s[has_diverged]}" == true ]]; then
          prompt+="$(omg_enrich_append true "-${s[commits_behind]} ${omg_has_diverged_symbol} +${s[commits_ahead]}" "${omg_setpp_remote_active}")"
        else
          if [[ "${s[commits_behind]}" -gt 0 ]]; then
            prompt+="$(omg_enrich_append true "-${s[commits_behind]} ${omg_setpp_remote_active}${omg_can_fast_forward_symbol}${omg_setpp_remote_inactive} --" "${omg_setpp_remote_inactive}")"
          fi

          if [[ "${s[commits_ahead]}" -gt 0 ]]; then
            prompt+="$(omg_enrich_append true "-- ${omg_setpp_remote_active}${omg_should_push_symbol}${omg_setpp_remote_inactive}  +${s[commits_ahead]}" "${omg_setpp_remote_inactive}")"
          fi

          if [[ "${s[commits_ahead]}" -eq 0 && "${s[commits_behind]}" -eq 0 ]]; then
            prompt+="$(omg_enrich_append true " --   -- " "${omg_setpp_remote_inactive}")"
          fi
        fi

        prompt+="$(omg_enrich_append true "(${s[current_branch]} ${type_of_upstream} ${s[upstream]//\/${s[current_branch]}/})" "${omg_setpp_remote_inactive}")"
      fi
    fi

    prompt+=$(omg_enrich_append "${s[is_on_a_tag]}" "${omg_is_on_a_tag_symbol} ${s[tag_at_current_commit]}" "${omg_setpp_remote_inactive}")
    prompt+="$(omg_eval_prompt_callback after_first)"
    prompt+="${omg_termination}"
    prompt+="\\n"
  fi

  prompt+="$(omg_eval_prompt_callback before_second)"
  prompt+="${prev_prompt}"
  prompt+="$(omg_eval_prompt_callback after_second)"

  echo "$prompt"
}

function omg_prompt_command() {
  local ret=$?
  PS1="$(omg_build_prompt)"
  return $ret
}

function omg_prompt_init() {
  [[ "$PROMPT_COMMAND" =~ omg_prompt_command ]] && return 0

  local prompt_cmd="$PROMPT_COMMAND"
  export PS2="${omg_yellow}→${omg_reset} "
  export PROMPT_COMMAND="${prompt_cmd}${prompt_cmd:+"; "}omg_prompt_command"
}

omg_prompt_init
