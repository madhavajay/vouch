use std/assert

use ../vouch/file.nu ["from td"]
use ../vouch/github.nu [
  can-manage
  gh-check-issue
  gh-check-pr
  gh-manage-by-issue
]
use helpers.nu [with-temp-vouched]

const REPO = "mitchellh/vouch"
const VOUCHED = "# Comment
-github:badguy old reason"

# --- gh-apply-action ---

export def "test gh-apply-action updates denounced reason" [] {
  with-temp-vouched $VOUCHED { |file|
    let result = do {
      nu -c (
        "source vouch/github.nu;"
        + " gh-apply-action denounce badguy 'new reason' "
        + $file
      )
    } | complete

    let contents = open --raw $file | from td
    let entry = $contents | where username == "badguy" | first

    assert equal $result.exit_code 0
    assert equal $entry.type "denounce"

    if $entry.details != "new reason" {
      error make {
        msg: (
          "expected denounced reason to update to "
          + $"'new reason', got '($entry.details)'"
        )
      }
    }
  }
}

# Skip the entire test if `gh` is not available
# or not authenticated.
def skip-without-gh [] {
  let has_gh = (which gh | length) > 0
  if not $has_gh {
    error make { msg: "SKIP: gh CLI not installed" }
  }

  let auth = do { gh auth status } | complete
  if $auth.exit_code != 0 {
    error make {
      msg: "SKIP: gh CLI not authenticated"
    }
  }
}

# --- gh-check-pr ---

export def "test slow gh-check-pr owner is vouched" [] {
  skip-without-gh

  # PR #48 is by mitchellh (repo owner / collaborator)
  let result = (
    gh-check-pr 48 -R $REPO --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow gh-check-pr vouched contributor" [] {
  skip-without-gh

  # PR #42 is by meherhendi (in the vouched list)
  let result = (
    gh-check-pr 42 -R $REPO --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow gh-check-pr unvouched user blocked" [] {
  skip-without-gh

  # PR #25 is by cipz (not in the vouched list,
  # not a collaborator)
  let result = (
    gh-check-pr 25 -R $REPO --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow gh-check-pr unvouched allowed without require-vouch" [] {
  skip-without-gh

  # PR #25 by cipz, with require-vouch=false
  let result = (
    gh-check-pr 25
      -R $REPO
      --require-vouch=false
      --dry-run=true
  )
  assert equal $result "allowed"
}

export def "test slow gh-check-pr auto-close dry-run" [] {
  skip-without-gh

  # PR #25 by cipz, with auto-close + dry-run
  let result = (
    gh-check-pr 25
      -R $REPO
      --auto-close=true
      --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow gh-check-pr bot is skipped" [] {
  skip-without-gh

  # PR #27 is by dependabot[bot]
  let result = (
    gh-check-pr 27 -R $REPO --dry-run=true
  )
  assert equal $result "skipped"
}

export def "test slow gh-check-pr missing repo errors" [] {
  skip-without-gh

  let result = (do {
    nu -c (
      'use vouch *; gh-check-pr 1 --dry-run=true'
    )
  } | complete)
  assert ($result.exit_code != 0)
}

# --- gh-check-issue ---

export def "test slow gh-check-issue owner is vouched" [] {
  skip-without-gh

  # Issue #46 is by mitchellh (repo owner)
  let result = (
    gh-check-issue 46 -R $REPO --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow gh-check-issue unvouched user blocked" [] {
  skip-without-gh

  # Issue #45 is by rsromanowski (not vouched)
  let result = (
    gh-check-issue 45 -R $REPO --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow gh-check-issue unvouched allowed without require-vouch" [] {
  skip-without-gh

  # Issue #45 by rsromanowski, require-vouch=false
  let result = (
    gh-check-issue 45
      -R $REPO
      --require-vouch=false
      --dry-run=true
  )
  assert equal $result "allowed"
}

export def "test slow gh-check-issue auto-close dry-run" [] {
  skip-without-gh

  let result = (
    gh-check-issue 45
      -R $REPO
      --auto-close=true
      --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow gh-check-issue vouched contributor" [] {
  skip-without-gh

  # Issue #41 is by DitherDude (vouched as ditherdude)
  let result = (
    gh-check-issue 41 -R $REPO --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow gh-check-issue missing repo errors" [] {
  skip-without-gh

  let result = (do {
    nu -c (
      'use vouch *; gh-check-issue 1 --dry-run=true'
    )
  } | complete)
  assert ($result.exit_code != 0)
}

# --- gh-manage-by-issue ---

export def "test slow gh-manage-by-issue non-matching comment" [] {
  skip-without-gh

  # Issue #45, comment 3872422330 body is a normal
  # reply, not a vouch/denounce keyword.
  let result = (
    gh-manage-by-issue 45 3872422330
      -R $REPO
      --dry-run=true
  )
  assert equal $result "unchanged"
}

export def "test slow gh-manage-by-issue missing repo errors" [] {
  skip-without-gh

  let result = (do {
    nu -c (
      'use vouch *;'
      + ' gh-manage-by-issue 1 999 --dry-run=true'
    )
  } | complete)
  assert ($result.exit_code != 0)
}

# --- gh-check-pr with custom vouched-file ---

export def "test slow gh-check-pr custom vouched-file" [] {
  skip-without-gh

  # Using a non-existent vouched file; mitchellh is
  # still a collaborator so result is vouched.
  let result = (
    gh-check-pr 48
      -R $REPO
      --vouched-file "nonexistent/VOUCHED.td"
      --dry-run=true
  )
  assert equal $result "vouched"
}

# --- gh-check-issue with separate vouched-repo ---

export def "test slow gh-check-issue with vouched-repo" [] {
  skip-without-gh

  # Use the same repo as vouched-repo; mitchellh is a
  # collaborator so result is vouched.
  let result = (
    gh-check-issue 46
      -R $REPO
      --vouched-repo $REPO
      --dry-run=true
  )
  assert equal $result "vouched"
}

# --- can-manage ---

export def "test slow can-manage owner has access" [] {
  skip-without-gh

  # mitchellh is the repo owner (admin)
  let result = (
    can-manage "mitchellh" "mitchellh" "vouch"
  )
  assert equal $result true
}

export def "test slow can-manage non-collaborator denied" [] {
  skip-without-gh

  # cipz is not a collaborator on mitchellh/vouch
  let result = (
    can-manage "mitchellh-nope" "mitchellh" "vouch"
  )
  assert equal $result false
}

export def "test slow can-manage with restrictive roles" [] {
  skip-without-gh

  # mitchellh is admin; restrict to only "maintain"
  # so admin should be denied
  let result = (
    can-manage "mitchellh" "mitchellh" "vouch"
      --roles [maintain]
  )
  assert equal $result false
}

export def "test slow can-manage with matching role" [] {
  skip-without-gh

  # mitchellh is admin; include "admin" in roles
  let result = (
    can-manage "mitchellh" "mitchellh" "vouch"
      --roles [admin]
  )
  assert equal $result true
}

export def "test slow can-manage legacy-permissions override" [] {
  skip-without-gh

  # With roles set (no legacy default) but
  # legacy-permissions explicitly including "admin"
  let result = (
    can-manage "mitchellh" "mitchellh" "vouch"
      --roles [maintain]
      --legacy-permissions [admin]
  )
  assert equal $result true
}

export def "test slow can-manage empty legacy with roles" [] {
  skip-without-gh

  # When roles is set, legacy perms default to [].
  # With non-matching roles and no legacy fallback,
  # access should be denied.
  let result = (
    can-manage "mitchellh" "mitchellh" "vouch"
      --roles [triage]
  )
  assert equal $result false
}
