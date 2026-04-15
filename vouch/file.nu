# Parse Trustdown format into structured data.
export def "from td" []: string -> list<record> {
  lines | each { parse-line }
}

# Convert structured data to Trustdown format.
export def "to td" []: list<record> -> string {
  each { format-line } | to text
}

# Open a VOUCHED file and return all the lines. The rest of the commands
# take these lines as input. This will preserve comments and ordering and
# whitespace.
#
# If no path is provided or the path doesn't exist, falls back to default-path
# when --default is true (the default).
export def open-file [
  path?: path  # Path to the VOUCHED file
  --default = true  # Fall back to default-path if path is missing or doesn't exist
] {
  let resolved = if $path == null {
    if $default {
      default-path
    } else {
      null
    }
  } else {
    $path
  }

  if ($resolved == null) or (not ($resolved | path exists)) {
    error make { msg: "VOUCHED file not found" }
  }

  open --raw $resolved | from td
}

# Parse a handle into platform and username components.
#
# Handles format: "platform:username" or just "username"
# Returns a record with {platform: string | null, username: string}
export def parse-handle [handle: string] {
  let parts = $handle | str downcase | split row ":" --number 2
  if ($parts | length) > 1 {
    {platform: ($parts | first), username: ($parts | get 1)}
  } else {
    {platform: null, username: ($parts | first)}
  }
}

# Initialize a new VOUCHED file at the given path with starter content.
#
# Creates parent directories if needed. The file includes an explanatory
# header pointing to github.com/mitchellh/vouch for details.
export def init-file [
  path: path  # Path where the VOUCHED file should be created
] {
  let parent = ($path | path dirname)
  if not ($parent | path exists) {
    mkdir $parent
  }

  "# Vouched contributors for this project.
#
# See https://github.com/mitchellh/vouch for details.
#
# Syntax:
#   - One handle per line (without @), sorted alphabetically.
#   - Optional platform prefix: platform:username (e.g., github:user).
#   - Denounce with minus prefix: -username or -platform:username.
#   - Optional details after a space following the handle.
#   - Optional key=value attributes after the handle, such as:
#       github:user cap=issue,pr
#   - Attr values with spaces must be double-quoted, such as:
#       github:user details=\"trusted reporter\"
#   - Attribute keys are serialized in sorted order.
#   - `cap=` values are lowercased, deduped, and sorted.
#   - Capability names use lowercase letters, numbers, and hyphens.
#   - `denounced` and `unknown` are reserved.
#   - `*` may only be used by itself.
" | save $path
}

# Find the default VOUCHED file by checking common locations.
#
# Checks for VOUCHED.td in the current directory first, then .github/VOUCHED.td.
# Returns null if neither exists.
export def default-path [] {
  if ("VOUCHED.td" | path exists) {
    "VOUCHED.td"
  } else if (".github/VOUCHED.td" | path exists) {
    ".github/VOUCHED.td"
  } else {
    null
  }
}

# Parse a single line of TD format.
def parse-line []: string -> record {
  let line = $in

  if ($line | str trim | is-empty) {
    return { type: "blank", platform: null, username: null, details: null, attrs: {} }
  }

  if ($line | str trim | str starts-with "#") {
    return { type: "comment", platform: null, username: null, details: $line, attrs: {} }
  }

  let trimmed = $line | str trim

  # Check for denounce prefix
  let is_denounce = $trimmed | str starts-with "-"
  let rest = if $is_denounce { $trimmed | str substring 1.. } else { $trimmed }

  # Split handle from details (first space separates them)
  let parts = $rest | split row " " --number 2
  let handle = $parts | first
  let tail = if ($parts | length) > 1 { $parts | get 1 } else { null }

  let parsed = parse-handle $handle
  let attrs = parse-attrs $tail
  let details = if ($attrs | is-empty) { $tail } else { $attrs.details? | default null }

  {
    type: (if $is_denounce { "denounce" } else { "vouch" })
    platform: $parsed.platform
    username: $parsed.username
    details: $details
    attrs: $attrs
  }
}

# Format a single record back to TD format.
def format-line []: record -> string {
  let rec = $in

  match $rec.type {
    "blank" => "",
    "comment" => $rec.details,
    _ => {
      let prefix = if $rec.type == "denounce" { "-" } else { "" }
      let handle = if $rec.platform != null {
        $"($rec.platform):($rec.username)"
      } else {
        $rec.username
      }
      # Prefer structured attrs like `github:alice cap=issue,pr` over
      # legacy trailing details like `-github:badguy AI slop`.
      let attrs = canonicalize-attrs ($rec.attrs? | default {})
      let attr_text = format-attrs $attrs
      let suffix = if ($attr_text | is-not-empty) {
        $" ($attr_text)"
      } else if $rec.details != null {
        $" ($rec.details)"
      } else {
        ""
      }
      $"($prefix)($handle)($suffix)"
    }
  }
}

# Parse an attribute tail into a record of key/value pairs.
#
# To preserve compatibility with legacy free-form details, the tail is
# only treated as structured when the first token is key=value and all
# remaining tokens are also key=value pairs.
def parse-attrs [tail?: string] {
  if ($tail == null) or (($tail | str trim) | is-empty) {
    return {}
  }

  mut attrs = {}
  mut rest = $tail | str trim
  while ($rest | is-not-empty) {
    let match = (
      $rest
      | parse -r '^(?<key>[^ =]+)=(?:"(?<quoted>(?:[^"\\]|\\.)*)"|(?<bare>[^ ]+))(?: (?<rest>.*))?$'
    )

    if ($match | is-empty) {
      return {}
    }

    let token = $match | first
    let key = $token.key
    let value = if (($token.quoted? | default null) != null) {
      unescape-attr-value $token.quoted
    } else {
      $token.bare
    }

    if ($key | is-empty) or ($value | is-empty) {
      return {}
    }

    $attrs = ($attrs | upsert $key $value)
    $rest = $token.rest? | default ""
  }

  $attrs
}

# Format a record of key/value pairs for Trustdown.
def format-attrs [attrs: record] {
  let keys = $attrs | transpose key value | get key | sort

  $keys
  | each { |key|
    let value = $attrs | get $key
    $"($key)=((format-attr-value $value))"
  }
  | str join " "
}

def canonicalize-attrs [attrs: record] {
  if ($attrs.cap? | default null) == "*" { $attrs | reject cap } else { $attrs }
}

def format-attr-value [value] {
  let text = $value | into string
  if (($text | str contains " ") or ($text | str contains '"') or ($text | str contains "\\")) {
    let escaped = (
      $text
      | str replace -a "\\" "\\\\"
      | str replace -a '"' '\\"'
    )
    $'"($escaped)"'
  } else {
    $text
  }
}

def unescape-attr-value [value: string] {
  $value
  | str replace -a '\\"' '"'
  | str replace -a "\\\\" "\\"
}
