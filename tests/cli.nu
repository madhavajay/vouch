use std/assert

use ../vouch/file.nu ["from td", "to td"]

def with-temp-vouched [block: closure] {
  let dir = mktemp -d
  let file = $dir | path join "VOUCHED.td"
  "# Comment
mitchellh
github:alice
-github:badguy" | save $file
  try {
    do $block $file
  } catch { |e|
    rm -rf $dir
    error make { msg: $e.msg }
  }
  rm -rf $dir
}

# --- add ---

export def "test cli add previews by default" [] {
  with-temp-vouched { |file|
    let output = nu -c $'use vouch *; add newuser --vouched-file ($file)'
    assert ($output | str contains "newuser")
    let contents = open --raw $file | from td
    let status_after = $contents | where username == "newuser"
    assert equal ($status_after | length) 0 "file should not be modified"
  }
}

export def "test cli add writes with --write" [] {
  with-temp-vouched { |file|
    nu -c $'use vouch *; add newuser --vouched-file ($file) --write'
    let contents = open --raw $file | from td
    let entry = $contents | where username == "newuser" | first
    assert equal $entry.type "vouch"
  }
}

export def "test cli add replaces denounced with --write" [] {
  with-temp-vouched { |file|
    nu -c $'use vouch *; add github:badguy --vouched-file ($file) --write'
    let contents = open --raw $file | from td
    let entry = $contents | where username == "badguy" | first
    assert equal $entry.type "vouch"
  }
}

# --- check ---

export def "test cli check vouched exits 0" [] {
  with-temp-vouched { |file|
    let result = do { nu -c $'use vouch *; check mitchellh --vouched-file ($file)' } | complete
    assert equal $result.exit_code 0
    assert ($result.stdout | str contains "vouched")
  }
}

export def "test cli check denounced exits 1" [] {
  with-temp-vouched { |file|
    let result = do { nu -c $'use vouch *; check github:badguy --vouched-file ($file)' } | complete
    assert equal $result.exit_code 1
    assert ($result.stdout | str contains "denounced")
  }
}

export def "test cli check unknown exits 2" [] {
  with-temp-vouched { |file|
    let result = do { nu -c $'use vouch *; check nobody --vouched-file ($file)' } | complete
    assert equal $result.exit_code 2
    assert ($result.stdout | str contains "unknown")
  }
}

# --- denounce ---

export def "test cli denounce previews by default" [] {
  with-temp-vouched { |file|
    let output = nu -c $'use vouch *; denounce eviluser --vouched-file ($file)'
    assert ($output | str contains "eviluser")
    let contents = open --raw $file | from td
    let entry = $contents | where username == "eviluser"
    assert equal ($entry | length) 0 "file should not be modified"
  }
}

export def "test cli denounce writes with --write" [] {
  with-temp-vouched { |file|
    nu -c $'use vouch *; denounce eviluser --vouched-file ($file) --write'
    let contents = open --raw $file | from td
    let entry = $contents | where username == "eviluser" | first
    assert equal $entry.type "denounce"
  }
}

export def "test cli denounce with reason" [] {
  with-temp-vouched { |file|
    nu -c $'use vouch *; denounce eviluser --vouched-file ($file) --write --reason "AI slop"'
    let contents = open --raw $file | from td
    let entry = $contents | where username == "eviluser" | first
    assert equal $entry.type "denounce"
    assert equal $entry.details "AI slop"
  }
}

# --- get-caps ---

export def "test cli get-caps prints wildcard for legacy entry" [] {
  with-temp-vouched { |file|
    let output = nu -c $'use vouch *; get-caps mitchellh --vouched-file ($file)'
    assert equal ($output | str trim) "*"
  }
}

# --- has-caps ---

export def "test cli has-caps prints true for legacy entry" [] {
  with-temp-vouched { |file|
    let output = nu -c $'use vouch *; has-caps mitchellh issue --vouched-file ($file)'
    assert equal ($output | str trim) "true"
  }
}

export def "test cli has-caps explicit prints false for legacy entry" [] {
  with-temp-vouched { |file|
    let output = nu -c $'use vouch *; has-caps mitchellh issue --vouched-file ($file) --explicit'
    assert equal ($output | str trim) "false"
  }
}

export def "test cli has-caps explicit prints true for explicit wildcard cap" [] {
  with-temp-vouched { |file|
    "# Comment
mitchellh
github:alice cap=*
-github:badguy
" | save -f $file
    let output = nu -c $'use vouch *; has-caps github:alice issue --vouched-file ($file) --explicit'
    assert equal ($output | str trim) "true"
  }
}

export def "test cli has-caps prints false for denied cap" [] {
  with-temp-vouched { |file|
    nu -c $'use vouch *; set-caps github:badguy issue --vouched-file ($file) --write'
    let output = nu -c $'use vouch *; has-caps github:badguy pr --vouched-file ($file)'
    assert equal ($output | str trim) "false"
  }
}

# --- set-caps ---

export def "test cli set-caps previews by default" [] {
  with-temp-vouched { |file|
    let output = nu -c $'use vouch *; set-caps alice issue --vouched-file ($file)'
    assert ($output | str contains "cap=issue")
    let contents = open --raw $file | from td
    let entry = $contents | where username == "alice" | first
    assert equal ($entry.attrs? | default {}) {}
  }
}

export def "test cli set-caps lifts denounced user with --write" [] {
  with-temp-vouched { |file|
    nu -c $'use vouch *; set-caps github:badguy issue --vouched-file ($file) --write'
    let contents = open --raw $file | from td
    let entry = $contents | where username == "badguy" | first
    assert equal $entry.type "vouch"
    assert equal $entry.attrs.cap "issue"
  }
}

export def "test cli set-caps rejects empty capability string" [] {
  with-temp-vouched { |file|
    let result = nu -c $'use vouch *; set-caps alice "" --vouched-file ($file)' | complete
    assert equal $result.exit_code 1
    assert ($result.stderr | str contains "must not be empty")
  }
}

# --- remove ---

export def "test cli remove previews by default" [] {
  with-temp-vouched { |file|
    let output = nu -c $'use vouch *; remove mitchellh --vouched-file ($file)'
    assert (not ($output | str contains "mitchellh")) "preview should not contain removed user"
    let contents = open --raw $file | from td
    let entry = $contents | where username == "mitchellh"
    assert equal ($entry | length) 1 "file should not be modified"
  }
}

export def "test cli remove writes with --write" [] {
  with-temp-vouched { |file|
    nu -c $'use vouch *; remove mitchellh --vouched-file ($file) --write'
    let contents = open --raw $file | from td
    let entry = $contents | where username == "mitchellh"
    assert equal ($entry | length) 0
  }
}

export def "test cli remove removes denounced with --write" [] {
  with-temp-vouched { |file|
    nu -c $'use vouch *; remove github:badguy --vouched-file ($file) --write'
    let contents = open --raw $file | from td
    let entry = $contents | where username == "badguy"
    assert equal ($entry | length) 0
  }
}

# Ensure commands work when --vouched-file isn't explicitly provided.
export def "test cli defaults vouched file path" [] {
  let dir = mktemp -d
  let file = $dir | path join "VOUCHED.td"
  "# Comment
mitchellh" | save $file

  try {
    nu -c $'cd ($dir); use vouch *; add newuser --write'
    let contents = open --raw $file | from td
    assert equal (($contents | where username == "newuser" | length)) 1
  } catch { |e|
    rm -rf $dir
    error make { msg: $e.msg }
  }

  rm -rf $dir
}
