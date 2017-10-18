function omg_current_action() {
  local info="$(git rev-parse --git-dir 2>/dev/null)"

  [[ -z "$info" ]] && return 1

  local action

  if [ -f "$info/rebase-merge/interactive" ]; then
    action="${is_rebasing_interactively:-"rebase -i"}"
  elif [ -d "$info/rebase-merge" ]; then
    action="${is_rebasing_merge:-"rebase -m"}"
  else
    if [ -d "$info/rebase-apply" ]; then
      if [ -f "$info/rebase-apply/rebasing" ]; then
        action="${is_rebasing:-"rebase"}"
      elif [ -f "$info/rebase-apply/applying" ]; then
        action="${is_applying_mailbox_patches:-"am"}"
      else
        action="${is_rebasing_mailbox_patches:-"am/rebase"}"
      fi
    elif [ -f "$info/MERGE_HEAD" ]; then
      action="${is_merging:-"merge"}"
    elif [ -f "$info/CHERRY_PICK_HEAD" ]; then
      action="${is_cherry_picking:-"cherry-pick"}"
    elif [ -f "$info/BISECT_LOG" ]; then
      action="${is_bisecting:-"bisect"}"
    fi
  fi

  [[ -n "$action" ]] && printf "%s" "${1-}$action${2-}"
}

function omg_build_prompt() {
  local enabled="${OMG_PROMPT_ENABLED:=true}"
  [[ -z "$enabled" ]] && enabled="$(git config --get oh-my-git.enabled 2> /dev/null)"

  if [[ ${enabled} == false ]]; then
    echo "${OMG_PS_ORIG}"
    exit
  fi

  local prompt=""

  # Git info
  local current_commit_hash="$(git rev-parse HEAD 2> /dev/null)"

  if [[ -n $current_commit_hash ]]; then local is_a_git_repo=true; fi

  if [[ $is_a_git_repo == true ]]; then
    local current_branch="$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"
    if [[ $current_branch == 'HEAD' ]]; then local detached=true; fi

    local number_of_logs="$(git log --pretty=oneline -n1 2> /dev/null | wc -l)"
    if [[ $number_of_logs -eq 0 ]]; then
      local just_init=true
    else
      local upstream="$(git rev-parse --symbolic-full-name --abbrev-ref @{upstream} 2> /dev/null)"
      if [[ -n "${upstream}" && "${upstream}" != "@{upstream}" ]]; then local has_upstream=true; fi

      local git_status="$(git status --porcelain 2> /dev/null)"
      local action="$(omg_current_action)"

      if [[ $git_status =~ ($'\n'|^).M ]]; then local has_modifications=true; fi
      if [[ $git_status =~ ($'\n'|^)M ]]; then local has_modifications_cached=true; fi
      if [[ $git_status =~ ($'\n'|^)A ]]; then local has_adds=true; fi
      if [[ $git_status =~ ($'\n'|^).D ]]; then local has_deletions=true; fi
      if [[ $git_status =~ ($'\n'|^)D ]]; then local has_deletions_cached=true; fi
      if [[ $git_status =~ ($'\n'|^)[MAD] && ! $git_status =~ ($'\n'|^).[MAD\?] ]]; then local ready_to_commit=true; fi

      local number_of_untracked_files=$(\grep -c "^??" <<< "${git_status}")
      if [[ $number_of_untracked_files -gt 0 ]]; then local has_untracked_files=true; fi

      local tag_at_current_commit=$(git describe --exact-match --tags $current_commit_hash 2> /dev/null)
      if [[ -n $tag_at_current_commit ]]; then local is_on_a_tag=true; fi

      if [[ $has_upstream == true ]]; then
          local commits_diff="$(git log --pretty=oneline --topo-order --left-right ${current_commit_hash}...${upstream} 2> /dev/null)"
          local commits_ahead=$(\grep -c "^<" <<< "$commits_diff")
          local commits_behind=$(\grep -c "^>" <<< "$commits_diff")
      fi

      if [[ $commits_ahead -gt 0 && $commits_behind -gt 0 ]]; then local has_diverged=true; fi
      if [[ $has_diverged == false && $commits_ahead -gt 0 ]]; then local should_push=true; fi

      local will_rebase="$(git config --get branch.${current_branch}.rebase 2> /dev/null)"
      local number_of_stashes="$(git stash list -n1 2> /dev/null | wc -l)"
      if [[ $number_of_stashes -gt 0 ]]; then local has_stashes=true; fi
    fi
  fi

  echo "$(omg_custom_build_prompt ${enabled:-true} ${current_commit_hash:-""} ${is_a_git_repo:-false} ${current_branch:-""} ${detached:-false} ${just_init:-false} ${has_upstream:-false} ${has_modifications:-false} ${has_modifications_cached:-false} ${has_adds:-false} ${has_deletions:-false} ${has_deletions_cached:-false} ${has_untracked_files:-false} ${ready_to_commit:-false} ${tag_at_current_commit:-""} ${is_on_a_tag:-false} ${has_upstream:-false} ${commits_ahead:-false} ${commits_behind:-false} ${has_diverged:-false} ${should_push:-false} ${will_rebase:-false} ${has_stashes:-false} ${action})"
}

function omg_exists() {
  declare -f -F "$1" > /dev/null
}

function omg_eval_prompt_callback() {
  local callback_name="omg_prompt_callback"
  [[ -n "$1" ]] && callback_name+="_$1"
  omg_exists "$callback_name" && $callback_name
}
