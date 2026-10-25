// Expected output: clap_complete's Nushell generator on the Rust
// equivalents of the commands in commands_test.mbt.

///|
test "nushell my-app" {
  inspect(
    @clap_complete.generate(Nushell, my_app(), "my-app"),
    content=(
      #|module completions {
      #|
      #|  def "nu-complete my-app color" [] {
      #|    [ "always" "never" "auto" ]
      #|  }
      #|
      #|  def "nu-complete my-app mode" [] {
      #|    [ "fast" "\"slow mode\"" ]
      #|  }
      #|
      #|  # My app
      #|  export extern my-app [
      #|    --verbose(-v)             # Verbosity [level]
      #|    --config(-c): path        # Config file: it's `$HOME`
      #|    --color: string@"nu-complete my-app color" # When to color
      #|    --mode: string@"nu-complete my-app mode"
      #|    --out(-o): directory      # Output directory
      #|    --output: directory       # Output directory
      #|    -O: directory             # Output directory
      #|    --name: string            # A name
      #|    --file: path              # Two files
      #|    --quiet(-q)               # Be quiet, please
      #|    --silent                  # Be quiet, please
      #|    -s                        # Be quiet, please
      #|    --secret
      #|    --help(-h)                # Print help (see more with '--help')
      #|    --version(-V)             # Print version
      #|  ]
      #|
      #|  def "nu-complete my-app build target" [] {
      #|    [ "x86" "arm" ]
      #|  }
      #|
      #|  # Build it
      #|  export extern "my-app build" [
      #|    --release                 # Release mode
      #|    --help(-h)                # Print help (see more with '--help')
      #|    target: string@"nu-complete my-app build target" # The [target]
      #|    ...inputs: path           # Input files
      #|  ]
      #|
      #|  # Clean up
      #|  export extern "my-app build clean" [
      #|    --help(-h)                # Print help
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "my-app build help" [
      #|  ]
      #|
      #|  # Clean up
      #|  export extern "my-app build help clean" [
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "my-app build help help" [
      #|  ]
      #|
      #|  # Run 'all' tests
      #|  export extern "my-app test-all" [
      #|    -j: string                # Jobs
      #|    --help(-h)                # Print help
      #|  ]
      #|
      #|  export extern "my-app hidden" [
      #|    --help(-h)                # Print help
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "my-app help" [
      #|  ]
      #|
      #|  # Build it
      #|  export extern "my-app help build" [
      #|  ]
      #|
      #|  # Clean up
      #|  export extern "my-app help build clean" [
      #|  ]
      #|
      #|  # Run 'all' tests
      #|  export extern "my-app help test-all" [
      #|  ]
      #|
      #|  export extern "my-app help hidden" [
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "my-app help help" [
      #|  ]
      #|
      #|}
      #|
      #|export use completions *
      #|
    ),
  )
}

///|
test "nushell nested" {
  inspect(
    @clap_complete.generate(Nushell, nested(), "nested"),
    content=(
      #|module completions {
      #|
      #|  export extern nested [
      #|    --help(-h)                # Print help
      #|  ]
      #|
      #|  # A
      #|  export extern "nested a" [
      #|    --help(-h)                # Print help
      #|  ]
      #|
      #|  # B
      #|  export extern "nested a b" [
      #|    --help(-h)                # Print help
      #|  ]
      #|
      #|  export extern "nested a b c" [
      #|    --help(-h)                # Print help
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "nested a b help" [
      #|  ]
      #|
      #|  export extern "nested a b help c" [
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "nested a b help help" [
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "nested a help" [
      #|  ]
      #|
      #|  # B
      #|  export extern "nested a help b" [
      #|  ]
      #|
      #|  export extern "nested a help b c" [
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "nested a help help" [
      #|  ]
      #|
      #|  export extern "nested d" [
      #|    --help(-h)                # Print help
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "nested help" [
      #|  ]
      #|
      #|  # A
      #|  export extern "nested help a" [
      #|  ]
      #|
      #|  # B
      #|  export extern "nested help a b" [
      #|  ]
      #|
      #|  export extern "nested help a b c" [
      #|  ]
      #|
      #|  export extern "nested help d" [
      #|  ]
      #|
      #|  # Print this message or the help of the given subcommand(s)
      #|  export extern "nested help help" [
      #|  ]
      #|
      #|}
      #|
      #|export use completions *
      #|
    ),
  )
}
