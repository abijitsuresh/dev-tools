######## ADD THIS TO .zshrc ###########

# -----------------------------------------------------------------------------
# SEARCH TOOLKIT (v2.8) - Archive Management & Smart Naming
# -----------------------------------------------------------------------------

# SETTINGS
CLEANUP_DAYS=30
ARCHIVE_MAX_GB=1
SEARCH_BASE_DIR="$HOME/Documents/searches"

_fzf_search_help() {
  echo "Usage: ${1} [search_text] [flags]"
  echo ""
  echo "Flags:"
  echo "  -e          Export to default folder ($SEARCH_BASE_DIR)"
  echo "  -eo         Export and Open folder in Finder"
  echo "  -ee         Export and Open in Neovim (at line)"
  echo "  -ec         Export to Current directory"
  echo "  -m          Enable Multi-selection (Use TAB)"
  echo "  -s          Case-Sensitive search"
  echo "  -d  [num]   Search depth (e.g., -d 1)"
  echo "  -t  [list]  Include types (comma-separated: -t js,ts)"
  echo "  -xt [list]  Exclude types (comma-separated: -xt json,md)"
  echo "  -his        View export history"
  echo "  -dry        Show the ripgrep command"
  echo "  -h          Show this help menu"
}

_fzf_save_and_action() {
  local result="$1" mode="$2" target_dir="$3" query_name="$4"
  local ts=$(date +%Y%m%d_%H%M%S)
  local folder_name=$(basename "$PWD")
  
  # Clean query name for filename safety
  local safe_query=$(echo "${query_name:-search}" | tr -cd '[:alnum:]_-' | cut -c 1-20)
  local default_file="${folder_name}_${safe_query}_$ts.txt"
  local archive_dir="$SEARCH_BASE_DIR/archive"

  # 1. ARCHIVE LOGIC: Move files older than CLEANUP_DAYS
  if [[ "$target_dir" == "$SEARCH_BASE_DIR" ]]; then
    mkdir -p "$archive_dir"
    find "$target_dir" -maxdepth 1 -name "*.txt" -type f -mtime +"$CLEANUP_DAYS" -exec mv {} "$archive_dir/" \; 2>/dev/null
    
    # 2. SIZE LIMIT LOGIC: Delete oldest files if archive > ARCHIVE_MAX_GB
    local current_size=$(du -sk "$archive_dir" | cut -f1)
    local max_kb=$(( ARCHIVE_MAX_GB * 1024 * 1024 ))
    if [ "$current_size" -gt "$max_kb" ]; then
      # Delete oldest until under limit
      find "$archive_dir" -type f -name "*.txt" -printf '%T+ %p\n' | sort | head -n 5 | cut -d' ' -f2- | xargs rm -f
    fi
  fi

  mkdir -p "$target_dir"
  echo -n "Enter filename (default: $default_file): "
  read filename
  filename=${filename:-$default_file}

  local full_path="$target_dir/$filename"
  echo "$result" > "$full_path"
  echo "Saved to $full_path"

  case "$mode" in
    folder) open "$target_dir" ;;
    editor)
      if [[ -n "$result" ]]; then
        local line_num=$(echo "$result" | head -n 1 | cut -d: -f2)
        if [[ "$line_num" =~ ^[0-9]+$ ]]; then
          command -v nvim >/dev/null && nvim +"$line_num" "$full_path" || vim +"$line_num" "$full_path"
        else
          command -v nvim >/dev/null && nvim "$full_path" || vim "$full_path"
        fi
      fi
      ;;
  esac
}

_fzf_search_engine() {
  local type="$1" query="$2"
  shift 2
  local fzf_opts="" rg_opts="" mode="none" do_export=false dry_run=false
  local dest="$SEARCH_BASE_DIR" globs=()

  [[ "$type" == "fif" ]] && rg_opts="--files-with-matches --no-messages" || rg_opts="--line-number"
  local ignore_list=(".git" "node_modules" "dist" "build" "vendor" ".next" "target")
  for dir in "${ignore_list[@]}"; do globs+=("--glob" "!$dir/*"); done

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h)   _fzf_search_help "$type"; return 0 ;;
      -his) ls -lh "$SEARCH_BASE_DIR"; echo "Archive:"; ls -lh "$SEARCH_BASE_DIR/archive" 2>/dev/null; return 0 ;;
      -dry) dry_run=true ;;
      -m)   fzf_opts="--multi" ;;
      -s)   rg_opts+=" --case-sensitive" ;;
      -e)   do_export=true ;;
      -eo)  do_export=true; mode="folder" ;;
      -ee)  do_export=true; mode="editor" ;;
      -ec)  do_export=true; dest="." ;;
      -d)   shift; rg_opts+=" --max-depth $1" ;;
      -t)   shift; IFS=',' read -ra ADDR <<< "$1"; for i in "${ADDR[@]}"; do globs+=("-t" "$i"); done ;;
      -xt)  shift; IFS=',' read -ra ADDR <<< "$1"; for i in "${ADDR[@]}"; do globs+=("-T" "$i"); done ;;
    esac
    shift
  done

  if [ "$dry_run" = true ]; then
    echo "rg $rg_opts ${globs[@]} \"$query\""; return 0
  fi

  local preview_cmd
  [[ "$type" == "fif" ]] && preview_cmd="highlight -O ansi -l {} 2>/dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$query' || rg --ignore-case --pretty --context 10 '$query' {}" || preview_cmd="echo {}"

  local result=$(rg $rg_opts "${globs[@]}" "$query" | fzf $fzf_opts --ansi --preview "$preview_cmd" --preview-window up:wrap)
  [ -z "$result" ] && return
  if [ "$do_export" = true ]; then _fzf_save_and_action "$result" "$mode" "$dest" "$query"; else echo "$result"; fi
}

fif() { _fzf_search_engine "fif" "$@"; }
fil() { _fzf_search_engine "fil" "$@"; }
