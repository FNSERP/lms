#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="${APP_DIR:-/home/frappe/frappe-bench/apps/lms}"
BENCH_DIR="${BENCH_DIR:-/home/frappe/frappe-bench}"
BENCH_BIN="${BENCH_BIN:-/home/frappe/.local/bin/bench}"
CUSTOM_REMOTE="${CUSTOM_REMOTE:-upstream}"
OFFICIAL_REMOTE="${OFFICIAL_REMOTE:-official}"
CUSTOM_BRANCH="${CUSTOM_BRANCH:-FNS}"
OFFICIAL_BRANCH="${OFFICIAL_BRANCH:-develop}"

APPLY=0
DEPLOY=0
SKIP_TESTS=0
AUTO_STASH=0
STASH_CREATED=0
STASH_MESSAGE=""
ORIGINAL_ARGS=("$@")

usage() {
	cat <<'EOF'
Usage: sync_lms_official.sh [options]

Safely merges official Frappe LMS updates into a temporary sync branch.

Options:
  --apply       Run tests, fast-forward FNS, and push it to FNSERP/lms.
  --deploy      Same as --apply, then run bench update --reset --apps lms.
  --stash       Stash tracked and untracked local changes before starting.
  --skip-tests  Skip frontend tests and build (not allowed with --deploy).
  -h, --help    Show this help.

Examples:
  scripts/sync_lms_official.sh
  scripts/sync_lms_official.sh --apply --stash
  scripts/sync_lms_official.sh --deploy --stash
EOF
}

log() {
	printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
	printf '\nERROR: %s\n' "$*" >&2
	exit 1
}

while (($#)); do
	case "$1" in
		--apply)
			APPLY=1
			;;
		--deploy)
			APPLY=1
			DEPLOY=1
			;;
		--stash)
			AUTO_STASH=1
			;;
		--skip-tests)
			SKIP_TESTS=1
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			die "Unknown option: $1"
			;;
	esac
	shift
done

if ((DEPLOY && SKIP_TESTS)); then
	die "--deploy cannot be combined with --skip-tests."
fi

if [[ "$(id -un)" != "frappe" ]]; then
	exec sudo -u frappe -H "$0" "${ORIGINAL_ARGS[@]}"
fi

[[ -d "$APP_DIR/.git" ]] || die "LMS repository not found: $APP_DIR"
[[ -x "$BENCH_BIN" ]] || die "Bench executable not found: $BENCH_BIN"

cd "$APP_DIR"

git remote get-url "$CUSTOM_REMOTE" >/dev/null 2>&1 ||
	die "Missing custom remote '$CUSTOM_REMOTE'."
git remote get-url "$OFFICIAL_REMOTE" >/dev/null 2>&1 ||
	die "Missing official remote '$OFFICIAL_REMOTE'."
git show-ref --verify --quiet "refs/heads/$CUSTOM_BRANCH" ||
	die "Missing local branch '$CUSTOM_BRANCH'."

if [[ -n "$(git status --porcelain)" ]]; then
	if ((AUTO_STASH)); then
		STASH_MESSAGE="lms-official-sync-$(date '+%Y%m%d-%H%M%S')"
		log "Stashing local changes as '$STASH_MESSAGE'"
		git stash push --include-untracked -m "$STASH_MESSAGE"
		STASH_CREATED=1
	else
		git status --short
		die "Working tree is not clean. Commit the changes or rerun with --stash."
	fi
fi

log "Updating $CUSTOM_BRANCH from $CUSTOM_REMOTE/$CUSTOM_BRANCH"
git fetch --no-tags "$CUSTOM_REMOTE"
git switch "$CUSTOM_BRANCH"
git merge --ff-only "$CUSTOM_REMOTE/$CUSTOM_BRANCH"

if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
	log "Unshallowing the repository from $OFFICIAL_REMOTE (one-time operation)"
	git fetch --unshallow --no-tags "$OFFICIAL_REMOTE"
fi

log "Fetching $OFFICIAL_REMOTE/$OFFICIAL_BRANCH"
git fetch --no-tags "$OFFICIAL_REMOTE" "$OFFICIAL_BRANCH"

if git merge-base --is-ancestor "$OFFICIAL_REMOTE/$OFFICIAL_BRANCH" "$CUSTOM_BRANCH"; then
	log "$CUSTOM_BRANCH already contains the latest official code."
	if ((STASH_CREATED)); then
		printf "Local leftovers remain saved in the stash named '%s'.\n" "$STASH_MESSAGE"
	fi
	exit 0
fi

SYNC_BRANCH="sync/official-$(date '+%Y%m%d-%H%M%S')"
log "Creating $SYNC_BRANCH"
git switch -c "$SYNC_BRANCH" "$CUSTOM_BRANCH"

log "Merging $OFFICIAL_REMOTE/$OFFICIAL_BRANCH"
if ! git merge --no-edit "$OFFICIAL_REMOTE/$OFFICIAL_BRANCH"; then
	printf '\nMerge conflicts were found. No code was discarded.\n' >&2
	printf 'Resolve the files shown by: git status\n' >&2
	printf 'Then run: git add <files> && git commit\n' >&2
	printf 'To cancel: git merge --abort && git switch %s\n' "$CUSTOM_BRANCH" >&2
	exit 2
fi

if ((!SKIP_TESTS)); then
	log "Running frontend tests"
	# shellcheck disable=SC1091
	source /home/frappe/.nvm/nvm.sh
	(
		cd frontend
		yarn vitest run --reporter=dot
	)

	log "Building production frontend"
	NODE_OPTIONS=--max-old-space-size=4096 yarn build
else
	log "Skipping tests and build by request"
fi

if ((!APPLY)); then
	log "Sync branch is ready for review: $SYNC_BRANCH"
	printf 'After review, execute:\n'
	printf '  git switch %s\n' "$CUSTOM_BRANCH"
	printf '  git merge --ff-only %s\n' "$SYNC_BRANCH"
	printf '  git push %s %s\n' "$CUSTOM_REMOTE" "$CUSTOM_BRANCH"
	if ((STASH_CREATED)); then
		printf "Local leftovers remain saved in the stash named '%s'.\n" "$STASH_MESSAGE"
	fi
	exit 0
fi

log "Applying verified sync to $CUSTOM_BRANCH"
git switch "$CUSTOM_BRANCH"
git merge --ff-only "$SYNC_BRANCH"
git push "$CUSTOM_REMOTE" "$CUSTOM_BRANCH"

if ((DEPLOY)); then
	log "Deploying LMS from $CUSTOM_REMOTE/$CUSTOM_BRANCH"
	cd "$BENCH_DIR"
	"$BENCH_BIN" update --reset --apps lms
fi

log "Official LMS update completed successfully"
if ((STASH_CREATED)); then
	printf "Local leftovers remain saved in the stash named '%s'.\n" "$STASH_MESSAGE"
	printf 'Inspect them with: git stash list\n'
fi
