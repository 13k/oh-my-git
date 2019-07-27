#!/bin/bash

[[ -z "$BASH_VERSION" ]] && return 0

OMG_MARK="omg_prompt_mark"
OMG_ESC_MARK="\\e_${OMG_MARK}\\e\\\\"
OMG_ORIGINAL_PS1="$PS1"

# colors
omg_reset='\[\e[0m\]'
omg_black='\[\e[0;30m\]'
omg_red='\[\e[0;31m\]'
omg_green='\[\e[0;32m\]'
omg_yellow='\[\e[0;33m\]'
omg_blue='\[\e[0;34m\]'
omg_purple='\[\e[0;35m\]'
omg_cyan='\[\e[0;36m\]'
omg_white='\[\e[0;37m\]'
omg_white_bold='\[\e[1;37m\]'
omg_bg_black='\[\e[40m\]'
omg_bg_red='\[\e[41m\]'
omg_bg_green='\[\e[42m\]'
omg_bg_yellow='\[\e[43m\]'
omg_bg_blue='\[\e[44m\]'
omg_bg_purple='\[\e[45m\]'
omg_bg_cyan='\[\e[46m\]'
omg_bg_white='\[\e[47m\]'
omg_black_on_white="${omg_black}${omg_bg_white}"
omg_yellow_on_white="${omg_yellow}${omg_bg_white}"
omg_purple_on_white="${omg_purple}${omg_bg_white}"
omg_red_on_white="${omg_red}${omg_bg_white}"
omg_red_on_black="${omg_red}${omg_bg_black}"
omg_black_on_red="${omg_black}${omg_bg_red}"
omg_white_on_red="${omg_white}${omg_bg_red}"
omg_yellow_on_red="${omg_yellow}${omg_bg_red}"

# config
: "${omg_separator_symbol:=''}"
: "${omg_terminator_symbol:="$omg_separator_symbol"}"
: "${omg_is_a_git_repo_symbol:=''}"
: "${omg_has_untracked_files_symbol:=''}"
: "${omg_has_adds_symbol:=''}"
: "${omg_has_deletions_symbol:=''}"
: "${omg_has_cached_deletions_symbol:=''}"
: "${omg_has_cached_modifications_symbol:=''}"
: "${omg_has_modifications_symbol:=''}"
: "${omg_ready_to_commit_symbol:=''}"
: "${omg_is_on_a_tag_symbol:=''}"
: "${omg_needs_to_merge_symbol:=''}"
: "${omg_detached_symbol:=''}"
: "${omg_can_fast_forward_symbol:=''}"
: "${omg_has_diverged_symbol:=''}"
: "${omg_not_tracked_branch_symbol:=''}"
: "${omg_rebase_tracking_branch_symbol:=''}"
: "${omg_merge_tracking_branch_symbol:=''}"
: "${omg_should_push_symbol:=''}"
: "${omg_has_stashes_symbol:=''}"

: "${omg_default_color_on:="$omg_white_bold"}"
: "${omg_default_color_off:="$omg_reset"}"
: "${omg_terminator_color:="$omg_red_on_black"}"

: "${omg_termination:="${omg_terminator_color}${omg_terminator_symbol}"}"

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
  local color="${3:-$omg_default_color_on}"
  [[ $flag == false ]] && symbol=' '
  echo -n "${color}${symbol}  "
}

function omg_detect_state() {
  local enabled="$OMG_PROMPT_ENABLED"

  if [[ -z "$enabled" ]]; then
		enabled="$(git config --get oh-my-git.enabled 2> /dev/null)"
	fi

  [[ $enabled == false ]] && return 1

	local is_git_repo=false
	local current_commit_hash
	local current_branch
	local is_detached=false
	local just_init=false
	local upstream
	local has_upstream=false
	local has_modifications=false
	local has_modifications_cached=false
	local has_adds=false
	local has_deletions=false
	local has_deletions_cached=false
	local has_untracked_files=false
	local ready_to_commit=false
	local tag_at_current_commit
	local is_on_a_tag=false
	local has_upstream=false
	local commits_ahead
	local commits_behind
	local has_diverged=false
	local should_push=false
	local will_rebase=false
	local has_stashes=false

  current_commit_hash="$(git rev-parse HEAD 2> /dev/null)"
	[[ -n "$current_commit_hash" ]] && is_git_repo=true

  if [[ $is_git_repo == true ]]; then
    current_branch="$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"
    [[ "$current_branch" == "HEAD" ]] && is_detached=true

		local number_of_logs
    number_of_logs="$(git log --pretty=oneline -n1 2> /dev/null | wc -l)"

    if [[ $number_of_logs -eq 0 ]]; then
      just_init=true
    else
			upstream="$(git rev-parse --symbolic-full-name --abbrev-ref "@{upstream}" 2> /dev/null)"
      [[ -n "${upstream}" && "${upstream}" != "@{upstream}" ]] && has_upstream=true

      local git_status
			git_status="$(git status --porcelain 2> /dev/null)"

      [[ "$git_status" =~ ($'\n'|^).M ]] && has_modifications=true
      [[ "$git_status" =~ ($'\n'|^)M ]] && has_modifications_cached=true
      [[ "$git_status" =~ ($'\n'|^)A ]] && has_adds=true
      [[ "$git_status" =~ ($'\n'|^).D ]] && has_deletions=true
      [[ "$git_status" =~ ($'\n'|^)D ]] && has_deletions_cached=true
      [[ "$git_status" =~ ($'\n'|^)[MAD] && ! "$git_status" =~ ($'\n'|^).[MAD\?] ]] && ready_to_commit=true

      local number_of_untracked_files
			number_of_untracked_files="$(\grep -c "^??" <<< "${git_status}")"
      [[ $number_of_untracked_files -gt 0 ]] && has_untracked_files=true

			tag_at_current_commit="$(git describe --exact-match --tags "$current_commit_hash" 2> /dev/null)"
      [[ -n "$tag_at_current_commit" ]] && is_on_a_tag=true

			local commits_diff
      if [[ $has_upstream == true ]]; then
				commits_diff="$(git log --pretty=oneline --topo-order --left-right "${current_commit_hash}...${upstream}" 2> /dev/null)"
				commits_ahead="$(\grep -c "^<" <<< "$commits_diff")"
				commits_behind="$(\grep -c "^>" <<< "$commits_diff")"
      fi

      [[ $commits_ahead -gt 0 && $commits_behind -gt 0 ]] && has_diverged=true
      [[ $has_diverged == false && $commits_ahead -gt 0 ]] && should_push=true

			local number_of_stashes
      will_rebase="$(git config --get "branch.${current_branch}.rebase" 2> /dev/null)"
      number_of_stashes="$(git stash list -n1 2> /dev/null | wc -l)"
      [[ $number_of_stashes -gt 0 ]] && has_stashes=true
    fi
  fi

	echo "$is_git_repo"
	echo "$current_commit_hash"
	echo "$current_branch"
	echo "$is_detached"
	echo "$just_init"
	echo "$upstream"
	echo "$has_upstream"
	echo "$has_modifications"
	echo "$has_modifications_cached"
	echo "$has_adds"
	echo "$has_deletions"
	echo "$has_deletions_cached"
	echo "$has_untracked_files"
	echo "$ready_to_commit"
	echo "$tag_at_current_commit"
	echo "$is_on_a_tag"
	echo "$has_upstream"
	echo "$commits_ahead"
	echo "$commits_behind"
	echo "$has_diverged"
	echo "$should_push"
	echo "$will_rebase"
	echo "$has_stashes"
}

function omg_previous_prompt() {
	if [[ "$PS1" == *${OMG_MARK}* ]]; then
		echo "$OMG_ORIGINAL_PS1"
	else
		echo "$PS1"
	fi
}

function omg_build_prompt() {
	local -a state_array
	local prev_prompt
	prev_prompt="$(omg_previous_prompt)"

	if ! readarray -t state_array <<< "$(omg_detect_state)"; then
		echo "$prev_prompt"
		return 0
	fi

	local -a state_vars=(
		"is_git_repo"
		"current_commit_hash"
		"current_branch"
		"is_detached"
		"just_init"
		"upstream"
		"has_upstream"
		"has_modifications"
		"has_modifications_cached"
		"has_adds"
		"has_deletions"
		"has_deletions_cached"
		"has_untracked_files"
		"ready_to_commit"
		"tag_at_current_commit"
		"is_on_a_tag"
		"has_upstream"
		"commits_ahead"
		"commits_behind"
		"has_diverged"
		"should_push"
		"will_rebase"
		"has_stashes"
	)

	if [[ ${#state_array[@]} -ne ${#state_vars[@]} ]]; then
		echo "$prev_prompt"
		return 0
	fi

	local state_var state_var_idx=0
	for state_var in "${state_vars[@]}"; do
		local "$state_var"="${state_array[$((state_var_idx++))]}"
	done

  local prompt="\\[$OMG_ESC_MARK\\]"

  if [[ $is_git_repo == true ]]; then
    # on filesystem
    prompt+="$(omg_eval_prompt_callback before_first)"
    prompt+="${omg_black_on_white} "
    prompt+="$(omg_enrich_append "$is_git_repo" "$omg_is_a_git_repo_symbol" "${omg_black_on_white}")"
    prompt+="$(omg_enrich_append "$has_stashes" "$omg_has_stashes_symbol" "${omg_red_on_white}")"
    prompt+="$(omg_enrich_append "$has_untracked_files" "$omg_has_untracked_files_symbol" "${omg_red_on_white}")"
    prompt+="$(omg_enrich_append "$has_modifications" "$omg_has_modifications_symbol" "${omg_red_on_white}")"
    prompt+="$(omg_enrich_append "$has_deletions" "$omg_has_deletions_symbol" "${omg_red_on_white}")"
    # ready
    prompt+="$(omg_enrich_append "$has_adds" "$omg_has_adds_symbol" "${omg_black_on_white}")"
    prompt+="$(omg_enrich_append "$has_modifications_cached" "$omg_has_cached_modifications_symbol" "${omg_black_on_white}")"
    prompt+="$(omg_enrich_append "$has_deletions_cached" "$omg_has_cached_deletions_symbol" "${omg_black_on_white}")"
    # next operation
    prompt+="$(omg_enrich_append "$ready_to_commit" "$omg_ready_to_commit_symbol" "${omg_red_on_white}")"
    # where
    prompt+=" ${omg_white_on_red}${omg_separator_symbol} ${omg_black_on_red}"

    if [[ $is_detached == true ]]; then
      prompt+="$(omg_enrich_append "$is_detached" "$omg_detached_symbol" "$omg_white_on_red")"
      prompt+="$(omg_enrich_append "$is_detached" "(${current_commit_hash:0:7})" "$omg_black_on_red")"
    else
      if [[ $has_upstream == false ]]; then
        prompt+="$(omg_enrich_append true "-- ${omg_not_tracked_branch_symbol}  --  (${current_branch})" "${omg_black_on_red}")"
      else
				local type_of_upstream

        if [[ $will_rebase == true ]]; then
          type_of_upstream="$omg_rebase_tracking_branch_symbol"
        else
          type_of_upstream="$omg_merge_tracking_branch_symbol"
        fi

        if [[ $has_diverged == true ]]; then
          prompt+="$(omg_enrich_append true "-${commits_behind} ${omg_has_diverged_symbol} +${commits_ahead}" "${omg_white_on_red}")"
        else
          if [[ $commits_behind -gt 0 ]]; then
            prompt+="$(omg_enrich_append true "-${commits_behind} ${omg_white_on_red}${omg_can_fast_forward_symbol}${omg_black_on_red} --" "${omg_black_on_red}")"
          fi

          if [[ $commits_ahead -gt 0 ]]; then
            prompt+="$(omg_enrich_append true "-- ${omg_white_on_red}${omg_should_push_symbol}${omg_black_on_red}  +${commits_ahead}" "${omg_black_on_red}")"
          fi

          if [[ $commits_ahead -eq 0 && $commits_behind -eq 0 ]]; then
            prompt+="$(omg_enrich_append true " --   -- " "${omg_black_on_red}")"
          fi
        fi

        prompt+="$(omg_enrich_append true "(${current_branch} ${type_of_upstream} ${upstream//\/$current_branch/})" "${omg_black_on_red}")"
      fi
    fi

    prompt+=$(omg_enrich_append "${is_on_a_tag}" "${omg_is_on_a_tag_symbol} ${tag_at_current_commit}" "${omg_black_on_red}")
    prompt+="$(omg_eval_prompt_callback after_first)"
    prompt+="${omg_termination}${omg_reset}"
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
