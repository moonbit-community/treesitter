// Expected output: clap_complete's Fish generator on the Rust
// equivalents of the commands in commands_test.mbt.

///|
test "fish my-app" {
  inspect(
    @clap_complete.generate(Fish, my_app(), "my-app"),
    content=(
      #|# Print an optspec for argparse to handle cmd's options that are independent of any subcommand.
      #|function __fish_my_app_global_optspecs
      #|    string join \n v/verbose c/config= color= mode= o/out= name= file= q/quiet secret h/help V/version
      #|end
      #|
      #|function __fish_my_app_needs_command
      #|    # Figure out if the current invocation already has a command.
      #|    set -l cmd (commandline -opc)
      #|    set -e cmd[1]
      #|    argparse -s (__fish_my_app_global_optspecs) -- $cmd 2>/dev/null
      #|    or return
      #|    if set -q argv[1]
      #|        # Also print the command, so this can be used to figure out what it is.
      #|        echo $argv[1]
      #|        return 1
      #|    end
      #|    return 0
      #|end
      #|
      #|function __fish_my_app_using_subcommand
      #|    set -l cmd (__fish_my_app_needs_command)
      #|    test -z "$cmd"
      #|    and return 1
      #|    contains -- $cmd[1] $argv
      #|end
      #|
      #|complete -c my-app -n "__fish_my_app_needs_command" -s c -l config -d 'Config file: it\'s `$HOME`' -r -F
      #|complete -c my-app -n "__fish_my_app_needs_command" -l color -d 'When to color' -r -f -a "always\t'Always color'
      #|never\t''"
      #|complete -c my-app -n "__fish_my_app_needs_command" -l mode -r -f -a "fast\t''
      #|slow mode\t''"
      #|complete -c my-app -n "__fish_my_app_needs_command" -s o -s O -l out -l output -d 'Output directory' -r -f -a "(__fish_complete_directories)"
      #|complete -c my-app -n "__fish_my_app_needs_command" -l name -d 'A name' -r -f
      #|complete -c my-app -n "__fish_my_app_needs_command" -l file -d 'Two files' -r -F
      #|complete -c my-app -n "__fish_my_app_needs_command" -s v -l verbose -d 'Verbosity [level]'
      #|complete -c my-app -n "__fish_my_app_needs_command" -s q -s s -l quiet -l silent -d 'Be quiet, please'
      #|complete -c my-app -n "__fish_my_app_needs_command" -l secret
      #|complete -c my-app -n "__fish_my_app_needs_command" -s h -l help -d 'Print help (see more with \'--help\')'
      #|complete -c my-app -n "__fish_my_app_needs_command" -s V -l version -d 'Print version'
      #|complete -c my-app -n "__fish_my_app_needs_command" -f -a "build" -d 'Build it'
      #|complete -c my-app -n "__fish_my_app_needs_command" -f -a "b" -d 'Build it'
      #|complete -c my-app -n "__fish_my_app_needs_command" -f -a "test-all" -d 'Run \'all\' tests'
      #|complete -c my-app -n "__fish_my_app_needs_command" -f -a "hidden"
      #|complete -c my-app -n "__fish_my_app_needs_command" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c my-app -n "__fish_my_app_using_subcommand build; and not __fish_seen_subcommand_from clean help" -l release -d 'Release mode'
      #|complete -c my-app -n "__fish_my_app_using_subcommand build; and not __fish_seen_subcommand_from clean help" -s h -l help -d 'Print help (see more with \'--help\')'
      #|complete -c my-app -n "__fish_my_app_using_subcommand build; and not __fish_seen_subcommand_from clean help" -a "clean" -d 'Clean up'
      #|complete -c my-app -n "__fish_my_app_using_subcommand build; and not __fish_seen_subcommand_from clean help" -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c my-app -n "__fish_my_app_using_subcommand build; and __fish_seen_subcommand_from clean" -s h -l help -d 'Print help'
      #|complete -c my-app -n "__fish_my_app_using_subcommand build; and __fish_seen_subcommand_from help" -f -a "clean" -d 'Clean up'
      #|complete -c my-app -n "__fish_my_app_using_subcommand build; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c my-app -n "__fish_my_app_using_subcommand b; and not __fish_seen_subcommand_from clean help" -l release -d 'Release mode'
      #|complete -c my-app -n "__fish_my_app_using_subcommand b; and not __fish_seen_subcommand_from clean help" -s h -l help -d 'Print help (see more with \'--help\')'
      #|complete -c my-app -n "__fish_my_app_using_subcommand b; and not __fish_seen_subcommand_from clean help" -a "clean" -d 'Clean up'
      #|complete -c my-app -n "__fish_my_app_using_subcommand b; and not __fish_seen_subcommand_from clean help" -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c my-app -n "__fish_my_app_using_subcommand b; and __fish_seen_subcommand_from clean" -s h -l help -d 'Print help'
      #|complete -c my-app -n "__fish_my_app_using_subcommand b; and __fish_seen_subcommand_from help" -f -a "clean" -d 'Clean up'
      #|complete -c my-app -n "__fish_my_app_using_subcommand b; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c my-app -n "__fish_my_app_using_subcommand test-all" -s j -d 'Jobs' -r
      #|complete -c my-app -n "__fish_my_app_using_subcommand test-all" -s h -l help -d 'Print help'
      #|complete -c my-app -n "__fish_my_app_using_subcommand hidden" -s h -l help -d 'Print help'
      #|complete -c my-app -n "__fish_my_app_using_subcommand help; and not __fish_seen_subcommand_from build test-all hidden help" -f -a "build" -d 'Build it'
      #|complete -c my-app -n "__fish_my_app_using_subcommand help; and not __fish_seen_subcommand_from build test-all hidden help" -f -a "test-all" -d 'Run \'all\' tests'
      #|complete -c my-app -n "__fish_my_app_using_subcommand help; and not __fish_seen_subcommand_from build test-all hidden help" -f -a "hidden"
      #|complete -c my-app -n "__fish_my_app_using_subcommand help; and not __fish_seen_subcommand_from build test-all hidden help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c my-app -n "__fish_my_app_using_subcommand help; and __fish_seen_subcommand_from build" -f -a "clean" -d 'Clean up'
      #|
    ),
  )
}

///|
test "fish nested" {
  inspect(
    @clap_complete.generate(Fish, nested(), "nested"),
    content=(
      #|# Print an optspec for argparse to handle cmd's options that are independent of any subcommand.
      #|function __fish_nested_global_optspecs
      #|    string join \n h/help
      #|end
      #|
      #|function __fish_nested_needs_command
      #|    # Figure out if the current invocation already has a command.
      #|    set -l cmd (commandline -opc)
      #|    set -e cmd[1]
      #|    argparse -s (__fish_nested_global_optspecs) -- $cmd 2>/dev/null
      #|    or return
      #|    if set -q argv[1]
      #|        # Also print the command, so this can be used to figure out what it is.
      #|        echo $argv[1]
      #|        return 1
      #|    end
      #|    return 0
      #|end
      #|
      #|function __fish_nested_using_subcommand
      #|    set -l cmd (__fish_nested_needs_command)
      #|    test -z "$cmd"
      #|    and return 1
      #|    contains -- $cmd[1] $argv
      #|end
      #|
      #|complete -c nested -n "__fish_nested_needs_command" -s h -l help -d 'Print help'
      #|complete -c nested -n "__fish_nested_needs_command" -f -a "a" -d 'A'
      #|complete -c nested -n "__fish_nested_needs_command" -f -a "d"
      #|complete -c nested -n "__fish_nested_needs_command" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c nested -n "__fish_nested_using_subcommand a; and not __fish_seen_subcommand_from b help" -s h -l help -d 'Print help'
      #|complete -c nested -n "__fish_nested_using_subcommand a; and not __fish_seen_subcommand_from b help" -f -a "b" -d 'B'
      #|complete -c nested -n "__fish_nested_using_subcommand a; and not __fish_seen_subcommand_from b help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c nested -n "__fish_nested_using_subcommand a; and __fish_seen_subcommand_from b" -s h -l help -d 'Print help'
      #|complete -c nested -n "__fish_nested_using_subcommand a; and __fish_seen_subcommand_from b" -f -a "c"
      #|complete -c nested -n "__fish_nested_using_subcommand a; and __fish_seen_subcommand_from b" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c nested -n "__fish_nested_using_subcommand a; and __fish_seen_subcommand_from help" -f -a "b" -d 'B'
      #|complete -c nested -n "__fish_nested_using_subcommand a; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c nested -n "__fish_nested_using_subcommand d" -s h -l help -d 'Print help'
      #|complete -c nested -n "__fish_nested_using_subcommand help; and not __fish_seen_subcommand_from a d help" -f -a "a" -d 'A'
      #|complete -c nested -n "__fish_nested_using_subcommand help; and not __fish_seen_subcommand_from a d help" -f -a "d"
      #|complete -c nested -n "__fish_nested_using_subcommand help; and not __fish_seen_subcommand_from a d help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
      #|complete -c nested -n "__fish_nested_using_subcommand help; and __fish_seen_subcommand_from a" -f -a "b" -d 'B'
      #|
    ),
  )
}
