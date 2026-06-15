use std/assert

use ../vouch/file.nu ["from td", "to td"]
use ../vouch/lib.nu [
  add-user
  check-user
  has-caps
  denounce-user
  get-caps
  parse-comment
  remove-user
  set-caps
]

def sample-records [] {
  "# Comment
mitchellh
github:alice
-github:badguy
-github:spammer Reason here" | from td
}

# --- check-user ---

export def "test check-user finds vouched user" [] {
  let result = sample-records | check-user "mitchellh"
  assert equal $result "vouched"
}

export def "test check-user finds vouched user with platform" [] {
  let result = sample-records | check-user "github:alice"
  assert equal $result "vouched"
}

export def "test check-user finds denounced user" [] {
  let result = sample-records | check-user "github:badguy"
  assert equal $result "denounced"
}

export def "test check-user returns unknown for missing user" [] {
  let result = sample-records | check-user "nobody"
  assert equal $result "unknown"
}

export def "test check-user is case insensitive" [] {
  let result = sample-records | check-user "MitchellH"
  assert equal $result "vouched"
}

export def "test check-user matches with default platform" [] {
  let result = sample-records | check-user "alice" --default-platform github
  assert equal $result "vouched"
}

export def "test check-user denounced with default platform" [] {
  let result = sample-records | check-user "badguy" --default-platform github
  assert equal $result "denounced"
}

export def "test has-caps defaults to caps=* for legacy entry" [] {
  let result = sample-records | has-caps "mitchellh" "issue"
  assert equal $result true
}

export def "test has-caps explicit denies legacy caps=*" [] {
  let result = sample-records | has-caps "mitchellh" "issue" --explicit
  assert equal $result false
}

export def "test has-caps explicit allows explicit wildcard cap" [] {
  let records = "github:alice cap=*" | from td
  let result = $records | has-caps "alice" "issue" --default-platform github --explicit
  assert equal $result true
}

export def "test has-caps denies denounced user" [] {
  let result = sample-records | has-caps "github:badguy" "issue"
  assert equal $result false
}

export def "test has-caps honors explicit capability list" [] {
  let records = "github:alice cap=issue" | from td
  assert equal (
    $records
    | has-caps "alice" "issue" --default-platform github
  ) true
  assert equal (
    $records
    | has-caps "alice" "pr" --default-platform github
  ) false
}

export def "test has-caps treats requested capabilities as a set" [] {
  let records = "github:alice cap=issue,pr" | from td
  assert equal (
    $records
    | has-caps "alice" "pr,issue" --default-platform github
  ) true
  assert equal (
    $records
    | has-caps "alice" "pr,review" --default-platform github
  ) false
}

# --- add-user ---

export def "test add-user adds new user" [] {
  let result = sample-records | add-user "newuser"
  let status = $result | check-user "newuser"
  assert equal $status "vouched"
}

export def "test add-user adds user with platform" [] {
  let result = sample-records | add-user "github:newuser"
  let status = $result | check-user "github:newuser"
  assert equal $status "vouched"
}

export def "test add-user replaces denounced user" [] {
  let result = sample-records | add-user "github:badguy"
  let status = $result | check-user "github:badguy"
  assert equal $status "vouched"
}

export def "test add-user preserves comments" [] {
  let result = sample-records | add-user "newuser"
  let comments = $result | where type == "comment"
  assert equal ($comments | length) 1
}

export def "test add-user result is sorted" [] {
  let result = sample-records | add-user "zzz"
  let entries = $result | where { |r| $r.type == "vouch" or $r.type == "denounce" }
  let usernames = $entries | get username
  let sorted = $usernames | sort -i
  assert equal $usernames $sorted
}

# --- denounce-user ---

export def "test denounce-user denounces a user" [] {
  let result = sample-records | denounce-user "newbad"
  let status = $result | check-user "newbad"
  assert equal $status "denounced"
}

export def "test denounce-user with reason" [] {
  let result = sample-records | denounce-user "newbad" "spam"
  let entry = $result | where username == "newbad" | first
  assert equal $entry.details "spam"
}

export def "test denounce-user replaces vouched user" [] {
  let result = sample-records | denounce-user "mitchellh"
  let status = $result | check-user "mitchellh"
  assert equal $status "denounced"
}

export def "test denounce-user preserves comments" [] {
  let result = sample-records | denounce-user "newbad"
  let comments = $result | where type == "comment"
  assert equal ($comments | length) 1
}

# --- get-caps ---

export def "test get-caps reports caps=* for legacy entry" [] {
  let result = sample-records | get-caps "mitchellh"
  assert equal $result.status "vouched"
  assert equal $result.caps ["*"]
  assert equal $result.explicit false
}

export def "test get-caps reports denounced user" [] {
  let result = sample-records | get-caps "github:badguy"
  assert equal $result.status "denounced"
  assert equal $result.caps []
}

export def "test get-caps reports explicit caps" [] {
  let records = "github:alice cap=issue,pr" | from td
  let result = $records | get-caps "alice" --default-platform github
  assert equal $result.status "vouched"
  assert equal $result.caps [issue pr]
  assert equal $result.explicit true
}

export def "test get-caps reports explicit wildcard" [] {
  let records = "github:alice cap=*" | from td
  let result = $records | get-caps "alice" --default-platform github
  assert equal $result.status "vouched"
  assert equal $result.caps ["*"]
  assert equal $result.explicit true
}

export def "test get-caps normalizes caps" [] {
  let records = "github:alice cap=PR,issue,issue" | from td
  let result = $records | get-caps "alice" --default-platform github
  assert equal $result.status "vouched"
  assert equal $result.caps [issue pr]
}

export def "test get-caps rejects reserved capability name" [] {
  let records = "github:alice cap=unknown" | from td
  try {
    $records | get-caps "alice" --default-platform github | ignore
    assert false
  } catch { |e|
    assert ($e.msg | str contains "reserved capability name")
  }
}

export def "test get-caps rejects invalid capability characters" [] {
  let records = "github:alice cap=some.*" | from td
  try {
    $records | get-caps "alice" --default-platform github | ignore
    assert false
  } catch { |e|
    assert ($e.msg | str contains "lowercase letters, numbers, and hyphens only")
  }
}

export def "test get-caps rejects wildcard mixed with other capabilities" [] {
  let records = "github:alice cap=*,pr" | from td
  try {
    $records | get-caps "alice" --default-platform github | ignore
    assert false
  } catch { |e|
    assert ($e.msg | str contains "`*` must be the only capability")
  }
}

# --- remove-user ---

export def "test remove-user removes vouched user" [] {
  let result = sample-records | remove-user "mitchellh"
  let status = $result | check-user "mitchellh"
  assert equal $status "unknown"
}

export def "test remove-user removes denounced user" [] {
  let result = sample-records | remove-user "github:badguy"
  let status = $result | check-user "github:badguy"
  assert equal $status "unknown"
}

export def "test remove-user preserves other entries" [] {
  let result = sample-records | remove-user "mitchellh"
  let status = $result | check-user "github:alice"
  assert equal $status "vouched"
}

export def "test remove-user preserves comments" [] {
  let result = sample-records | remove-user "mitchellh"
  let comments = $result | where type == "comment"
  assert equal ($comments | length) 1
}

export def "test remove-user noop for missing user" [] {
  let before = sample-records
  let after = $before | remove-user "nobody"
  assert equal ($after | length) ($before | length)
}

# --- set-caps ---

export def "test set-caps lifts denounce and applies caps" [] {
  let result = sample-records | set-caps "github:badguy" [issue]
  let status = $result | check-user "github:badguy"
  let caps = $result | get-caps "github:badguy"
  assert equal $status "vouched"
  assert equal $caps.caps [issue]
}

export def "test set-caps normalizes caps" [] {
  let result = sample-records | set-caps "github:alice" [pr issue issue]
  let entry = $result | where username == "alice" | first
  let caps = $result | get-caps "github:alice"
  assert equal $entry.attrs.cap "issue,pr"
  assert equal $caps.caps [issue pr]
}

export def "test set-caps rejects empty capability list" [] {
  try {
    sample-records | set-caps "github:alice" [] | ignore
    assert false
  } catch { |e|
    assert ($e.msg | str contains "must not be empty")
  }
}

export def "test has-caps rejects empty requested capability list" [] {
  try {
    sample-records | has-caps "mitchellh" "" | ignore
    assert false
  } catch { |e|
    assert ($e.msg | str contains "must not be empty")
  }
}

# --- roundtrip ---

export def "test add-user roundtrips through td format" [] {
  let result = sample-records | add-user "newuser" | to td | from td | check-user "newuser"
  assert equal $result "vouched"
}

export def "test denounce-user roundtrips through td format" [] {
  let result = sample-records | denounce-user "newbad" "reason" | to td | from td | check-user "newbad"
  assert equal $result "denounced"
}

# --- parse-comment ---

export def "test parse-comment vouch keyword only" [] {
  let result = parse-comment "vouch"
  assert equal $result.action "vouch"
  assert equal $result.user null
  assert equal $result.reason ""
}

export def "test parse-comment vouch with user" [] {
  let result = parse-comment "vouch @alice"
  assert equal $result.action "vouch"
  assert equal $result.user "alice"
  assert equal $result.reason ""
}

export def "test parse-comment vouch with user and reason" [] {
  let result = parse-comment "vouch @alice good contributor"
  assert equal $result.action "vouch"
  assert equal $result.user "alice"
  assert equal $result.reason "good contributor"
}

export def "test parse-comment vouch with reason no user" [] {
  let result = parse-comment "vouch trusted person"
  assert equal $result.action "vouch"
  assert equal $result.user null
  assert equal $result.reason "trusted person"
}

export def "test parse-comment denounce keyword only" [] {
  let result = parse-comment "denounce"
  assert equal $result.action "denounce"
  assert equal $result.user null
  assert equal $result.reason ""
}

export def "test parse-comment denounce with user and reason" [] {
  let result = parse-comment "denounce @badguy spammer"
  assert equal $result.action "denounce"
  assert equal $result.user "badguy"
  assert equal $result.reason "spammer"
}

export def "test parse-comment unvouch keyword only" [] {
  let result = parse-comment "unvouch"
  assert equal $result.action "unvouch"
  assert equal $result.user null
  assert equal $result.reason ""
}

export def "test parse-comment unvouch with user" [] {
  let result = parse-comment "unvouch @alice"
  assert equal $result.action "unvouch"
  assert equal $result.user "alice"
  assert equal $result.reason ""
}

export def "test parse-comment unvouch ignores trailing text" [] {
  let result = parse-comment "unvouch @alice some reason"
  assert equal $result.action null
}

export def "test parse-comment no match" [] {
  let result = parse-comment "hello world"
  assert equal $result.action null
  assert equal $result.user null
  assert equal $result.reason ""
}

export def "test parse-comment case insensitive" [] {
  let result = parse-comment "VOUCH @Alice"
  assert equal $result.action "vouch"
  assert equal $result.user "Alice"
}

export def "test parse-comment leading whitespace" [] {
  let result = parse-comment "  vouch @alice"
  assert equal $result.action "vouch"
  assert equal $result.user "alice"
}

export def "test parse-comment custom keyword" [] {
  let result = parse-comment "lgtm @alice" --vouch-keyword [lgtm approve]
  assert equal $result.action "vouch"
  assert equal $result.user "alice"
}

export def "test parse-comment allow-vouch false" [] {
  let result = parse-comment "vouch @alice" --allow-vouch=false
  assert equal $result.action null
}

export def "test parse-comment allow-denounce false" [] {
  let result = parse-comment "denounce @badguy" --allow-denounce=false
  assert equal $result.action null
}

export def "test parse-comment allow-unvouch false" [] {
  let result = parse-comment "unvouch @alice" --allow-unvouch=false
  assert equal $result.action null
}

export def "test parse-comment newline injection parses first line only" [] {
  let result = parse-comment "denounce @user\n-github:victim injected"
  assert equal $result.action "denounce"
  assert equal $result.user "user"
  assert equal $result.reason ""
}

export def "test parse-comment multiline body parses first line only" [] {
  let result = parse-comment "denounce @ditherdude\n-github:someLegitContributor haha"
  assert equal $result.action "denounce"
  assert equal $result.user "ditherdude"
  assert equal $result.reason ""
}

