#!/usr/bin/env nu

use file.nu [default-path, "from td", open-file, "to td"]
use lib.nu
use lib.nu [add-user, check-user, denounce-user, remove-user]

# Add a user to the vouched contributors list.
#
# This adds the user to the vouched list, removing any existing entry
# (vouched or denounced) for that user first.
#
# Examples:
#
#   # Preview new file contents (default)
#   ./vouch.nu add someuser
#
#   # Write the file in-place
#   ./vouch.nu add someuser --write
#
#   # Add with platform prefix
#   ./vouch.nu add github:someuser --write
#
export def add [
  username: string,          # Username to vouch for (supports platform:user format)
  --default-platform: string = "", # Assumed platform for entries without explicit platform
  --vouched-file: string = "",    # Path to vouched contributors file (default: VOUCHED.td or .github/VOUCHED.td)
  --write (-w),              # Write the file in-place (default: output to stdout)
] {
  let file = resolve-vouched-file $vouched_file
  let records = open-file $file
  let new_records = $records | add-user $username --default-platform $default_platform

  if $write {
    $new_records | to td | save -f $file
    print $"Added ($username) to vouched contributors"
  } else {
    print -n ($new_records | to td)
  }
}

# Check a user's vouch status.
#
# This checks if a user is vouched, denounced, or unknown.
#
# Exit codes:
#   0 - vouched
#   1 - denounced
#   2 - unknown
#
# Examples:
#
#   ./vouch.nu check someuser
#   ./vouch.nu check github:someuser
#
export def check [
  username: string,          # Username to check (supports platform:user format)
  --default-platform: string = "", # Assumed platform for entries without explicit platform
  --vouched-file: string = "",    # Path to vouched contributors file (default: VOUCHED.td or .github/VOUCHED.td)
] {
  let file = resolve-vouched-file $vouched_file
  let records = open-file $file
  let status = $records | check-user $username --default-platform $default_platform

  match $status {
    "vouched" => {
      print $"($username) is vouched"
      if not $nu.is-interactive { exit 0 }
    }
    "denounced" => {
      print $"($username) is denounced"
      if not $nu.is-interactive { exit 1 }
    }
    _ => {
      print $"($username) is unknown"
      if not $nu.is-interactive { exit 2 }
    }
  }
}

# Denounce a user by adding them to the VOUCHED file with a minus prefix.
#
# This removes any existing entry for the user and adds them as denounced.
# An optional reason can be provided which will be added after the username.
#
# Examples:
#
#   # Preview new file contents (default)
#   ./vouch.nu denounce badactor
#
#   # Denounce with a reason
#   ./vouch.nu denounce badactor --reason "Submitted AI slop"
#
#   # Write the file in-place
#   ./vouch.nu denounce badactor --write
#
#   # Denounce with platform prefix
#   ./vouch.nu denounce github:badactor --write
#
export def denounce [
  username: string,          # Username to denounce (supports platform:user format)
  --default-platform: string = "", # Assumed platform for entries without explicit platform
  --reason: string,          # Optional reason for denouncement
  --vouched-file: string = "",    # Path to vouched contributors file (default: VOUCHED.td or .github/VOUCHED.td)
  --write (-w),              # Write the file in-place (default: output to stdout)
] {
  let file = resolve-vouched-file $vouched_file
  let records = open-file $file
  let new_records = $records | denounce-user $username ($reason | default "") --default-platform $default_platform

  if $write {
    $new_records | to td | save -f $file
    print $"Denounced ($username)"
  } else {
    print -n ($new_records | to td)
  }
}

# Print a user's granted capabilities.
#
# Outputs one of:
#   - *
#   - comma-separated capabilities such as issue,pr
#   - denounced
#   - unknown
#
# Examples:
#
#   ./vouch.nu get-caps someuser
#   ./vouch.nu get-caps github:someuser
#
export def "get-caps" [
  username: string,          # Username to inspect (supports platform:user format)
  --default-platform: string = "", # Assumed platform for entries without explicit platform
  --vouched-file: string = "",    # Path to vouched contributors file (default: VOUCHED.td or .github/VOUCHED.td)
] {
  let file = resolve-vouched-file $vouched_file
  let records = open-file $file
  let result = $records | lib get-caps $username --default-platform $default_platform

  match $result.status {
    "unknown" => { print "unknown" }
    "denounced" => { print "denounced" }
    _ => {
      if $result.caps == ["*"] {
        print "*"
      } else {
        print ($result.caps | str join ",")
      }
    }
  }
}

# Check whether a user has one or more capabilities.
#
# Prints `true` when the user is allowed for the requested capability set
# and `false` otherwise. Capabilities are comma-separated, and order does
# not matter because they are treated as a set. Use `--explicit` to
# require the capability to be explicitly listed instead of inherited
# from implicit full access.
#
# Examples:
#
#   ./vouch.nu has-caps someuser issue
#   ./vouch.nu has-caps github:someuser issue,pr
#   ./vouch.nu has-caps mitchellh issue --explicit
#
export def "has-caps" [
  username: string,          # Username to check (supports platform:user format)
  capabilities: string,      # Capability or CSV, such as issue or issue,pr
  --default-platform: string = "", # Assumed platform for entries without explicit platform
  --vouched-file: string = "",    # Path to vouched contributors file (default: VOUCHED.td or .github/VOUCHED.td)
  --explicit,                # Require the capability to be explicitly listed
] {
  let file = resolve-vouched-file $vouched_file
  let records = open-file $file
  let result = $records | lib has-caps $username $capabilities --default-platform $default_platform --explicit=$explicit
  print $result
}

# Print CLI usage.
#
# This is primarily useful if you `use vouch *` and want a quick reminder
# of the available commands.
export def main [] {
  print "Usage: vouch <command>"
  print ""
  print "Local Commands:"
  print "  add               Add a user to the vouched contributors list"
  print "  check             Check a user's vouch status"
  print "  denounce          Denounce a user by adding them to the vouched file"
  print "  has-caps          Check whether a user has a capability"
  print "  get-caps          Print a user's granted capabilities"
  print "  remove            Remove a user from the vouched contributors list"
  print "  set-caps          Set a user's explicit capabilities"
  print ""
  print "GitHub integration:"
  print "  gh-check-pr         Check if a PR author is a vouched contributor"
  print "  gh-sync-codeowners  Sync CODEOWNERS entries into the VOUCHED list"
  print "  gh-manage-by-discussion Manage contributor status via discussion comment"
  print "  gh-manage-by-issue  Manage contributor status via issue comment"
}

# Remove a user from the VOUCHED file entirely.
#
# This removes any existing entry (vouched or denounced) for the user.
# The user will become unknown after this operation.
#
# Examples:
#
#   # Preview new file contents (default)
#   ./vouch.nu remove someuser
#
#   # Write the file in-place
#   ./vouch.nu remove someuser --write
#
#   # Remove with platform prefix
#   ./vouch.nu remove github:someuser --write
#
export def remove [
  username: string,          # Username to remove (supports platform:user format)
  --default-platform: string = "", # Assumed platform for entries without explicit platform
  --vouched-file: string = "",    # Path to vouched contributors file (default: VOUCHED.td or .github/VOUCHED.td)
  --write (-w),              # Write the file in-place (default: output to stdout)
] {
  let file = resolve-vouched-file $vouched_file
  let records = open-file $file
  let new_records = $records | remove-user $username --default-platform $default_platform

  if $write {
    $new_records | to td | save -f $file
    print $"Removed ($username) from vouched contributors"
  } else {
    print -n ($new_records | to td)
  }
}

# Set a user's explicit capabilities.
#
# This removes any prior vouch or denounce entry for the user, then adds
# a positive entry with the provided capabilities. Use `*` to clear any
# explicit cap list and return to the implicit full-access default.
#
# Examples:
#
#   # Preview a restricted issue-only entry
#   ./vouch.nu set-caps someuser issue
#
#   # Allow both issues and PRs
#   ./vouch.nu set-caps someuser issue,pr --write
#
#   # Restore implicit full access
#   ./vouch.nu set-caps someuser '*' --write
#
export def "set-caps" [
  username: string,          # Username to update (supports platform:user format)
  caps: string,              # Capability CSV or `*`
  --default-platform: string = "", # Assumed platform for entries without explicit platform
  --vouched-file: string = "",    # Path to vouched contributors file (default: VOUCHED.td or .github/VOUCHED.td)
  --write (-w),              # Write the file in-place (default: output to stdout)
] {
  let file = resolve-vouched-file $vouched_file
  let records = open-file $file
  let normalized_caps = parse-cli-caps $caps
  let new_records = if $normalized_caps == null {
    $records | add-user $username --default-platform $default_platform
  } else {
    $records
    | lib set-caps $username $normalized_caps --default-platform $default_platform
  }

  if $write {
    $new_records | to td | save -f $file
    print $"Set capabilities for ($username)"
  } else {
    print -n ($new_records | to td)
  }
}

# Print CLI usage as a normal (non-special) command.
#
# Nushell treats a top-level `main` as special, so it won't be imported by
# `use vouch *`. Exporting `vouch main` keeps help/call working in-module.
export def "vouch main" [] {
  main
}

# Parse the user-supplied CLI capability string.
def parse-cli-caps [caps: string] {
  let normalized = $caps | str trim | str downcase
  if $normalized == "*" {
    return null
  }

  let parsed = (
    $normalized
  | split row ","
  | each { |cap| $cap | str trim }
  | where { |cap| $cap != "" }
  | uniq
  )

  if ($parsed | is-empty) {
    error make { msg: "capabilities must not be empty; use `*` to restore full access" }
  }

  $parsed
}

def resolve-vouched-file [vouched_file: string] {
  if ($vouched_file | is-not-empty) {
    return $vouched_file
  }

  let default = default-path
  if ($default | is-empty) {
    error make { msg: "no VOUCHED file found" }
  }

  $default
}
