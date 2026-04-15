# Library functions for vouch contributor management.

use file.nu [parse-handle]

# Add a user to the VOUCHED table, removing any existing entry first.
#
# Supports platform:username format (e.g., github:mitchellh).
# Returns the updated table with the user added and sorted.
export def add-user [
  username: string,            # Username to add (supports platform:user format)
  --cap: list<string> = [],      # Optional capabilities to grant
  --default-platform: string = "", # Assumed platform for entries without explicit platform
  --details: string = "",      # Optional details/reason for vouching
]: table -> table {
  let handle = parse-handle $username
  let d = if ($details | is-empty) { null } else { $details }
  let attrs = caps-to-attrs $cap
  $in |
    remove-user $username --default-platform $default_platform |
    append ({
      type: "vouch"
      platform: $handle.platform
      username: $handle.username
      details: $d
      attrs: $attrs
    }) |
    sort-table
}

# Denounce a user in the VOUCHED table, removing any existing entry first.
#
# Supports platform:username format (e.g., github:mitchellh).
# Returns the updated table with the user added as denounced and sorted.
export def denounce-user [
  username: string,            # Username to denounce (supports platform:user format)
  reason: string = "",         # Reason for denouncement (can be empty)
  --default-platform: string = "", # Assumed platform for entries without explicit platform
]: table -> table {
  let handle = parse-handle $username

  $in |
    remove-user $username --default-platform $default_platform |
    append ({
      type: "denounce"
      platform: $handle.platform
      username: $handle.username
      details: (if ($reason | is-empty) { null } else { $reason })
      attrs: {}
    }) |
    sort-table
}

# Check a user's status in a VOUCHED table.
#
# Takes a table as returned by file.nu's `from td`.
# Supports platform:username format (e.g., github:mitchellh).
# Returns "vouched", "denounced", or "unknown".
export def check-user [
  username: string,            # Username to check (supports platform:user format)
  --default-platform: string = "", # Assumed platform for entries without explicit platform
]: table -> string {
  let entry = (find-user-entry $username --default-platform $default_platform)

  match $entry {
    null => "unknown"
    {type: "denounce"} => "denounced"
    _ => "vouched"
  }
}

# Check whether a user has a specific capability.
#
# Legacy positive entries without a `cap=` attribute are treated as
# having all capabilities.
export def "caps-allow" [
  granted: list<string>,         # Granted capabilities, such as [issue pr] or ["*"]
  wanted,                        # Capability or CSV capability list
]: nothing -> bool {
  let required = normalize-caps $wanted
  ($granted == ["*"]) or ($required | all { |cap| $cap in $granted })
}

# Check whether a user has a specific capability.
#
# Legacy positive entries without a `cap=` attribute are treated as
# having all capabilities unless `--explicit` is set.
export def "has-caps" [
  username: string,            # Username to check (supports platform:user format)
  caps,                        # Capability or CSV capability list
  --default-platform: string = "", # Assumed platform for entries without explicit platform
  --explicit,                  # Require the capability to be explicitly listed
]: table -> bool {
  let granted = ($in | get-caps $username --default-platform $default_platform)

  if $granted.status != "vouched" {
    return false
  }

  if $explicit and (not $granted.explicit) {
    return false
  }

  caps-allow $granted.caps $caps
}

# Get a user's capability information from the VOUCHED table.
#
#
# Returns a record with:
#   - status: "vouched", "denounced", or "unknown"
#   - caps: ["*"] for full access, or explicit capabilities when present
export def "get-caps" [
  username: string,            # Username to inspect (supports platform:user format)
  --default-platform: string = "", # Assumed platform for entries without explicit platform
]: table -> record {
  let entry = ($in | find-user-entry $username --default-platform $default_platform)

  if $entry == null {
    return { status: "unknown", caps: [] }
  }

  if $entry.type == "denounce" {
    return { status: "denounced", caps: [], explicit: false }
  }

  let granted = get-entry-capabilities $entry
  {
    status: "vouched"
    caps: $granted.caps
    explicit: $granted.explicit
  }
}

# Remove a user from the VOUCHED table (whether vouched or denounced).
#
# Comments and blank lines are preserved.
# Supports platform:username format (e.g., github:mitchellh).
# Returns the filtered table after removal.
export def remove-user [
  username: string,            # Username to remove (supports platform:user format)
  --default-platform: string = "", # Assumed platform for entries without explicit platform
]: table -> table {
  let records = $in
  let handle = parse-handle $username
  let default_platform_lower = normalize-platform $default_platform

  $records | where { |r|
    # Keep non-contributor entries (comments, blanks) unchanged
    if $r.type != "vouch" and $r.type != "denounce" {
      return true
    }

    # Normalize platforms: use default if not specified
    let entry_platform = normalize-entry-platform $r $default_platform_lower
    let entry_user = $r.username | str downcase
    let check_platform = if ($handle.platform == null) {
      $default_platform_lower
    } else {
      $handle.platform
    }

    # Platforms match if either is unspecified (null) or they're equal
    let platform_matches = (
      ($check_platform == null)
      or ($entry_platform == null)
      or ($entry_platform == $check_platform)
    )

    # Keep entries that don't match (remove those that do)
    not (($entry_user == $handle.username) and $platform_matches)
  }
}

# Parse a comment body to detect a vouch, denounce, or unvouch action.
#
# Returns a record with:
#   - action: "vouch", "denounce", "unvouch", or null if no match
#   - user: target username (or null if not specified)
#   - reason: reason string (or "" if not specified; always "" for unvouch)
#
# Examples:
#
#   parse-comment "vouch"
#   # => {action: vouch, user: null, reason: ""}
#
#   parse-comment "vouch @alice good work"
#   # => {action: vouch, user: alice, reason: "good work"}
#
#   parse-comment "denounce @badguy spammer"
#   # => {action: denounce, user: badguy, reason: spammer}
#
#   parse-comment "random text"
#   # => {action: null, user: null, reason: ""}
#
export def parse-comment [
  body: string,                                     # Comment body to parse
  --vouch-keyword: list<string> = ["vouch"],        # Keywords that trigger vouching
  --denounce-keyword: list<string> = ["denounce"],  # Keywords that trigger denouncing
  --unvouch-keyword: list<string> = ["unvouch"],    # Keywords that trigger unvouching
  --allow-vouch = true,                             # Enable vouch matching
  --allow-denounce = true,                          # Enable denounce matching
  --allow-unvouch = true,                           # Enable unvouch matching
]: nothing -> record {
  let trimmed = ($body | str trim | lines | first | str trim)

  if $allow_vouch {
    let joined = ($vouch_keyword | str join '|')
    let pattern = (
      '(?i)^[ \t]*('
      + $joined
      + ')(?:[ \t]+@(\S+))?(?:[ \t]+(.+))?$'
    )
    let m = $trimmed | parse -r $pattern
    if ($m | is-not-empty) {
      let match = $m | first
      return {
        action: "vouch"
        user: (if ($match.capture1? | default "" | is-empty) {
            null
          } else {
            $match.capture1
          })
        reason: ($match.capture2? | default "")
      }
    }
  }

  if $allow_denounce {
    let joined = ($denounce_keyword | str join '|')
    let pattern = (
      '(?i)^[ \t]*('
      + $joined
      + ')(?:[ \t]+@(\S+))?(?:[ \t]+(.+))?$'
    )
    let m = $trimmed | parse -r $pattern
    if ($m | is-not-empty) {
      let match = $m | first
      return {
        action: "denounce"
        user: (if ($match.capture1? | default "" | is-empty) {
            null
          } else {
            $match.capture1
          })
        reason: ($match.capture2? | default "")
      }
    }
  }

  if $allow_unvouch {
    let joined = ($unvouch_keyword | str join '|')
    let pattern = (
      '(?i)^[ \t]*('
      + $joined
      + ')(?:[ \t]+@(\S+))?[ \t]*$'
    )
    let m = $trimmed | parse -r $pattern
    if ($m | is-not-empty) {
      let match = $m | first
      return {
        action: "unvouch"
        user: (if ($match.capture1? | default "" | is-empty) {
            null
          } else {
            $match.capture1
          })
        reason: ""
      }
    }
  }

  { action: null, user: null, reason: "" }
}

# Set a user's explicit capabilities in the VOUCHED table.
#
# This lifts any existing denounce entry and replaces the user's record
# with a positive entry using the provided capabilities.
export def "set-caps" [
  username: string,            # Username to update (supports platform:user format)
  caps: list<string>,            # Capabilities such as [issue pr]
  --default-platform: string = "", # Assumed platform for entries without explicit platform
]: table -> table {
  if ($caps | is-empty) {
    error make { msg: "capabilities must not be empty; use `*` to restore full access" }
  }

  $in | add-user $username --cap $caps --default-platform $default_platform
}

# Convert a capability list into entry attrs.
def caps-to-attrs [caps: list<string>] {
  if ($caps | is-empty) {
    return {}
  }

  {
    cap: (
      normalize-caps $caps | str join ","
    )
  }
}

# Find the first matching contributor entry for a user.
def find-user-entry [
  username: string,
  --default-platform: string = "",
] {
  let records = $in
  let handle = parse-handle $username
  let default_platform_lower = normalize-platform $default_platform

  let contributors = (
    $records
    | where { |r| $r.type == "vouch" or $r.type == "denounce" }
  )

  for entry in $contributors {
    let entry_platform = normalize-entry-platform $entry $default_platform_lower
    let entry_user = $entry.username | str downcase
    let check_platform = if ($handle.platform == null) {
      $default_platform_lower
    } else {
      $handle.platform
    }
    let platform_matches = (
      ($check_platform == null)
      or ($entry_platform == null)
      or ($entry_platform == $check_platform)
    )

    if ($entry_user == $handle.username) and $platform_matches {
      return $entry
    }
  }

  null
}

# Return normalized capability metadata for an entry.
def get-entry-capabilities [entry: record] {
  let cap_value = $entry.attrs?.cap? | default null
  if $cap_value == null {
    return { caps: ["*"], explicit: false }
  }

  let normalized = normalize-caps $cap_value

  { caps: $normalized, explicit: true }
}

# Normalize capability input into a sorted, deduped, lowercase list.
def normalize-caps [caps] {
  # Accept either a CSV string from CLI-style callers or a list from lib
  # callers, then normalize both into the same set representation.
  let raw = if ($caps | describe) == "string" {
    $caps | split row ","
  } else {
    $caps
  }

  let normalized = (
    $raw
  | each { |cap| $cap | into string | str trim | str downcase }
  | where { |cap| $cap != "" }
  | uniq
  | sort
  )

  if ($normalized | is-empty) {
    error make { msg: "capabilities must not be empty" }
  }

  if ("*" in $normalized) and (($normalized | length) > 1) {
    error make { msg: "`*` must be the only capability" }
  }

  for cap in $normalized {
    if $cap in ["denounced" "unknown"] {
      error make { msg: $"`($cap)` is a reserved capability name" }
    }

    if ($cap != "*") and (($cap | parse -r '^[a-z0-9-]+$') | is-empty) {
      error make {
        msg: $"invalid capability `($cap)`: use lowercase letters, numbers, and hyphens only"
      }
    }
  }

  $normalized
}

# Normalize a platform value to lower-case or null.
def normalize-platform [platform: string] {
  if ($platform | is-empty) { null } else { $platform | str downcase }
}

# Normalize an entry platform, falling back to the default platform.
def normalize-entry-platform [entry: record, default_platform] {
  if ($entry.platform == null) { $default_platform } else { $entry.platform | str downcase }
}

# Helper: Sort table preserving comments/blanks at top, then entries alphabetically.
def sort-table []: table -> table {
  let records = $in
  let header = $records | where { |r| $r.type != "vouch" and $r.type != "denounce" }
  let entries = $records | where { |r| $r.type == "vouch" or $r.type == "denounce" }
  $header | append ($entries | sort-by -i username)
}
