export def with-temp-vouched [
  contents: string,
  block: closure,
] {
  let dir = mktemp -d
  let file = $dir | path join "VOUCHED.td"
  $contents | save $file

  try {
    do $block $file
  } catch { |e|
    rm -rf $dir
    error make { msg: $e.msg }
  }

  rm -rf $dir
}
