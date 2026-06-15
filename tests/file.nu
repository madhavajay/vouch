use std/assert

use ../vouch/file.nu ["from td", init-file, "to td", parse-handle]

def vouch-record [cap?: string, details?: string] {
  let attrs = if $cap == null {
    (if $details == null { {} } else { {details: $details} })
  } else if $details == null {
    {cap: $cap}
  } else {
    {details: $details, cap: $cap}
  }

  [[type platform username details attrs]; ["vouch" "github" "alice" ($details | default null) $attrs]]
}

# --- from td ---

export def "test from-td parses vouch entry" [] {
  let result = "mitchellh" | from td
  assert equal ($result | length) 1
  assert equal ($result | first | get type) "vouch"
  assert equal ($result | first | get username) "mitchellh"
  assert equal ($result | first | get platform) null
}

export def "test from-td parses platform vouch entry" [] {
  let result = "github:mitchellh" | from td
  assert equal ($result | first | get type) "vouch"
  assert equal ($result | first | get platform) "github"
  assert equal ($result | first | get username) "mitchellh"
}

export def "test from-td parses denounce entry" [] {
  let result = "-badguy" | from td
  assert equal ($result | first | get type) "denounce"
  assert equal ($result | first | get username) "badguy"
  assert equal ($result | first | get platform) null
}

export def "test from-td parses denounce with platform" [] {
  let result = "-github:badguy" | from td
  assert equal ($result | first | get type) "denounce"
  assert equal ($result | first | get platform) "github"
  assert equal ($result | first | get username) "badguy"
}

export def "test from-td parses denounce with details" [] {
  let result = "-github:slopmaster AI slop" | from td
  let entry = $result | first
  assert equal $entry.type "denounce"
  assert equal $entry.platform "github"
  assert equal $entry.username "slopmaster"
  assert equal $entry.details "AI slop"
}

export def "test from-td parses capability attrs" [] {
  let result = "github:alice cap=issue,pr" | from td
  let entry = $result | first
  assert equal $entry.type "vouch"
  assert equal $entry.username "alice"
  assert equal $entry.details null
  assert equal $entry.attrs.cap "issue,pr"
}

export def "test from-td parses multiple attrs" [] {
  let result = "github:alice cap=issue,pr details=trusted" | from td
  let entry = $result | first
  assert equal $entry.type "vouch"
  assert equal $entry.username "alice"
  assert equal $entry.details "trusted"
  assert equal $entry.attrs.cap "issue,pr"
  assert equal $entry.attrs.details "trusted"
}

export def "test from-td parses quoted attr value with spaces" [] {
  let result = 'github:alice cap=issue,pr details="trusted reporter"' | from td
  let entry = $result | first
  assert equal $entry.type "vouch"
  assert equal $entry.username "alice"
  assert equal $entry.details "trusted reporter"
  assert equal $entry.attrs.cap "issue,pr"
  assert equal $entry.attrs.details "trusted reporter"
}

export def "test from-td parses comment" [] {
  let result = "# This is a comment" | from td
  assert equal ($result | first | get type) "comment"
  assert equal ($result | first | get details) "# This is a comment"
}

export def "test from-td parses blank line" [] {
  let result = "mitchellh\n\nalice" | from td
  assert equal ($result | get 1 | get type) "blank"
}

export def "test from-td parses full file" [] {
  let input = "# Comment
mitchellh
github:alice
-github:badguy
-github:spammer Reason here"
  let result = $input | from td
  assert equal ($result | length) 5
  assert equal ($result | get 0 | get type) "comment"
  assert equal ($result | get 1 | get type) "vouch"
  assert equal ($result | get 1 | get username) "mitchellh"
  assert equal ($result | get 2 | get type) "vouch"
  assert equal ($result | get 2 | get platform) "github"
  assert equal ($result | get 3 | get type) "denounce"
  assert equal ($result | get 4 | get details) "Reason here"
}

# --- to td ---

export def "test to-td formats vouch entry" [] {
  let result = [{type: "vouch", platform: null, username: "mitchellh", details: null}] | to td
  assert equal ($result | str trim) "mitchellh"
}

export def "test to-td formats platform vouch entry" [] {
  let result = [{type: "vouch", platform: "github", username: "mitchellh", details: null}] | to td
  assert equal ($result | str trim) "github:mitchellh"
}

export def "test to-td formats denounce entry" [] {
  let result = [{type: "denounce", platform: null, username: "badguy", details: null}] | to td
  assert equal ($result | str trim) "-badguy"
}

export def "test to-td formats denounce with details" [] {
  let result = [{type: "denounce", platform: "github", username: "badguy", details: "AI slop"}] | to td
  assert equal ($result | str trim) "-github:badguy AI slop"
}

export def "test to-td formats capability attrs" [] {
  assert equal ((vouch-record "issue,pr" | to td | str trim)) "github:alice cap=issue,pr"
}

export def "test to-td omits wildcard capability attr" [] {
  assert equal ((vouch-record "*" | to td | str trim)) "github:alice"
}

export def "test to-td quotes attr value with spaces" [] {
  assert equal ((vouch-record "issue,pr" "trusted reporter" | to td | str trim)) 'github:alice cap=issue,pr details="trusted reporter"'
}

export def "test to-td sorts attribute keys" [] {
  assert equal ((vouch-record "issue,pr" "trusted" | to td | str trim)) 'github:alice cap=issue,pr details=trusted'
}

export def "test to-td formats comment" [] {
  let result = [{type: "comment", platform: null, username: null, details: "# A comment"}] | to td
  assert equal ($result | str trim) "# A comment"
}

export def "test to-td formats blank" [] {
  let result = [{type: "blank", platform: null, username: null, details: null}] | to td
  assert equal $result "\n"
}

export def "test from-td to-td roundtrip" [] {
  let input = "# Comment
mitchellh
github:alice
-github:badguy
-github:spammer Reason here"
  let result = $input | from td | to td | str trim
  assert equal $result $input
}

# --- parse-handle ---

export def "test parse-handle simple username" [] {
  let result = parse-handle "mitchellh"
  assert equal $result.platform null
  assert equal $result.username "mitchellh"
}

export def "test parse-handle with platform" [] {
  let result = parse-handle "github:mitchellh"
  assert equal $result.platform "github"
  assert equal $result.username "mitchellh"
}

# --- init-file ---

export def "test init-file creates file with header" [] {
  let dir = mktemp -d
  let file = $dir | path join ".github" "VOUCHED.td"
  try {
    init-file $file
    assert ($file | path exists)
    let content = open --raw $file
    assert ($content | str contains "https://github.com/mitchellh/vouch")
    let records = $content | from td
    let entries = $records | where { |r| $r.type == "vouch" or $r.type == "denounce" }
    assert equal ($entries | length) 0
  } catch { |e|
    rm -rf $dir
    error make { msg: $e.msg }
  }
  rm -rf $dir
}

export def "test parse-handle normalizes case" [] {
  let result = parse-handle "GitHub:MitchellH"
  assert equal $result.platform "github"
  assert equal $result.username "mitchellh"
}
