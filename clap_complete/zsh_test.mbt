// Expected output: clap_complete's Zsh generator on the Rust
// equivalents of the commands in commands_test.mbt.

///|
test "zsh my-app" {
  inspect(
    @clap_complete.generate(Zsh, my_app(), "my-app"),
    content=(
      #|#compdef my-app
      #|
      #|autoload -U is-at-least
      #|
      #|_my-app() {
      #|    typeset -A opt_args
      #|    typeset -a _arguments_options
      #|    local ret=1
      #|
      #|    if is-at-least 5.2; then
      #|        _arguments_options=(-s -S -C)
      #|    else
      #|        _arguments_options=(-s -C)
      #|    fi
      #|
      #|    local context curcontext="$curcontext" state line
      #|    _arguments "${_arguments_options[@]}" : \
      #|'-c+[Config file\: it'\''s \`\$HOME\`]:FILE:_files' \
      #|'--config=[Config file\: it'\''s \`\$HOME\`]:FILE:_files' \
      #|'--color=[When to color]:WHEN:((always\:"Always color"
      #|never\:""))' \
      #|'--mode=[]:MODE:(fast slow\ mode)' \
      #|'(-v --verbose)-o+[Output directory]:DIR:_files -/' \
      #|'(-v --verbose)-O+[Output directory]:DIR:_files -/' \
      #|'(-v --verbose)--out=[Output directory]:DIR:_files -/' \
      #|'(-v --verbose)--output=[Output directory]:DIR:_files -/' \
      #|'*--name=[A name]:NAME:' \
      #|'--file=[Two files]:F:_files:F:_files' \
      #|'*-v[Verbosity \[level\]]' \
      #|'*--verbose[Verbosity \[level\]]' \
      #|'-q[Be quiet, please]' \
      #|'-s[Be quiet, please]' \
      #|'--quiet[Be quiet, please]' \
      #|'--silent[Be quiet, please]' \
      #|'--secret[]' \
      #|'-h[Print help (see more with '\''--help'\'')]' \
      #|'--help[Print help (see more with '\''--help'\'')]' \
      #|'-V[Print version]' \
      #|'--version[Print version]' \
      #|":: :_my-app_commands" \
      #|"*::: :->my-app" \
      #|&& ret=0
      #|    case $state in
      #|    (my-app)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:my-app-command-$line[1]:"
      #|        case $line[1] in
      #|            (build)
      #|_arguments "${_arguments_options[@]}" : \
      #|'--release[Release mode]' \
      #|'-h[Print help (see more with '\''--help'\'')]' \
      #|'--help[Print help (see more with '\''--help'\'')]' \
      #|':target -- The \[target\]:((x86\:"Intel"
      #|arm\:""))' \
      #|'::inputs -- Input files:_files' \
      #|":: :_my-app__subcmd__build_commands" \
      #|"*::: :->build" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (build)
      #|        words=($line[3] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:my-app-build-command-$line[3]:"
      #|        case $line[3] in
      #|            (clean)
      #|_arguments "${_arguments_options[@]}" : \
      #|'-h[Print help]' \
      #|'--help[Print help]' \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_my-app__subcmd__build__subcmd__help_commands" \
      #|"*::: :->help" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (help)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:my-app-build-help-command-$line[1]:"
      #|        case $line[1] in
      #|            (clean)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|(b)
      #|_arguments "${_arguments_options[@]}" : \
      #|'--release[Release mode]' \
      #|'-h[Print help (see more with '\''--help'\'')]' \
      #|'--help[Print help (see more with '\''--help'\'')]' \
      #|':target -- The \[target\]:((x86\:"Intel"
      #|arm\:""))' \
      #|'::inputs -- Input files:_files' \
      #|":: :_my-app__subcmd__build_commands" \
      #|"*::: :->build" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (build)
      #|        words=($line[3] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:my-app-build-command-$line[3]:"
      #|        case $line[3] in
      #|            (clean)
      #|_arguments "${_arguments_options[@]}" : \
      #|'-h[Print help]' \
      #|'--help[Print help]' \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_my-app__subcmd__build__subcmd__help_commands" \
      #|"*::: :->help" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (help)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:my-app-build-help-command-$line[1]:"
      #|        case $line[1] in
      #|            (clean)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|(test-all)
      #|_arguments "${_arguments_options[@]}" : \
      #|'-j+[Jobs]::N:_default' \
      #|'-h[Print help]' \
      #|'--help[Print help]' \
      #|&& ret=0
      #|;;
      #|(hidden)
      #|_arguments "${_arguments_options[@]}" : \
      #|'-h[Print help]' \
      #|'--help[Print help]' \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_my-app__subcmd__help_commands" \
      #|"*::: :->help" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (help)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:my-app-help-command-$line[1]:"
      #|        case $line[1] in
      #|            (build)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_my-app__subcmd__help__subcmd__build_commands" \
      #|"*::: :->build" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (build)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:my-app-help-build-command-$line[1]:"
      #|        case $line[1] in
      #|            (clean)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|(test-all)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|(hidden)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|}
      #|
      #|(( $+functions[_my-app_commands] )) ||
      #|_my-app_commands() {
      #|    local commands; commands=(
      #|'build:Build it' \
      #|'b:Build it' \
      #|'test-all:Run '\''all'\'' tests' \
      #|'hidden:' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'my-app commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__build_commands] )) ||
      #|_my-app__subcmd__build_commands() {
      #|    local commands; commands=(
      #|'clean:Clean up' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'my-app build commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__build__subcmd__clean_commands] )) ||
      #|_my-app__subcmd__build__subcmd__clean_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'my-app build clean commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__build__subcmd__help_commands] )) ||
      #|_my-app__subcmd__build__subcmd__help_commands() {
      #|    local commands; commands=(
      #|'clean:Clean up' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'my-app build help commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__build__subcmd__help__subcmd__clean_commands] )) ||
      #|_my-app__subcmd__build__subcmd__help__subcmd__clean_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'my-app build help clean commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__build__subcmd__help__subcmd__help_commands] )) ||
      #|_my-app__subcmd__build__subcmd__help__subcmd__help_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'my-app build help help commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__help_commands] )) ||
      #|_my-app__subcmd__help_commands() {
      #|    local commands; commands=(
      #|'build:Build it' \
      #|'test-all:Run '\''all'\'' tests' \
      #|'hidden:' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'my-app help commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__help__subcmd__build_commands] )) ||
      #|_my-app__subcmd__help__subcmd__build_commands() {
      #|    local commands; commands=(
      #|'clean:Clean up' \
      #|    )
      #|    _describe -t commands 'my-app help build commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__help__subcmd__build__subcmd__clean_commands] )) ||
      #|_my-app__subcmd__help__subcmd__build__subcmd__clean_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'my-app help build clean commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__help__subcmd__help_commands] )) ||
      #|_my-app__subcmd__help__subcmd__help_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'my-app help help commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__help__subcmd__hidden_commands] )) ||
      #|_my-app__subcmd__help__subcmd__hidden_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'my-app help hidden commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__help__subcmd__test-all_commands] )) ||
      #|_my-app__subcmd__help__subcmd__test-all_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'my-app help test-all commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__hidden_commands] )) ||
      #|_my-app__subcmd__hidden_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'my-app hidden commands' commands "$@"
      #|}
      #|(( $+functions[_my-app__subcmd__test-all_commands] )) ||
      #|_my-app__subcmd__test-all_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'my-app test-all commands' commands "$@"
      #|}
      #|
      #|if [ "$funcstack[1]" = "_my-app" ]; then
      #|    _my-app "$@"
      #|else
      #|    compdef _my-app my-app
      #|fi
      #|
    ),
  )
}

///|
test "zsh nested" {
  inspect(
    @clap_complete.generate(Zsh, nested(), "nested"),
    content=(
      #|#compdef nested
      #|
      #|autoload -U is-at-least
      #|
      #|_nested() {
      #|    typeset -A opt_args
      #|    typeset -a _arguments_options
      #|    local ret=1
      #|
      #|    if is-at-least 5.2; then
      #|        _arguments_options=(-s -S -C)
      #|    else
      #|        _arguments_options=(-s -C)
      #|    fi
      #|
      #|    local context curcontext="$curcontext" state line
      #|    _arguments "${_arguments_options[@]}" : \
      #|'-h[Print help]' \
      #|'--help[Print help]' \
      #|":: :_nested_commands" \
      #|"*::: :->nested" \
      #|&& ret=0
      #|    case $state in
      #|    (nested)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:nested-command-$line[1]:"
      #|        case $line[1] in
      #|            (a)
      #|_arguments "${_arguments_options[@]}" : \
      #|'-h[Print help]' \
      #|'--help[Print help]' \
      #|":: :_nested__subcmd__a_commands" \
      #|"*::: :->a" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (a)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:nested-a-command-$line[1]:"
      #|        case $line[1] in
      #|            (b)
      #|_arguments "${_arguments_options[@]}" : \
      #|'-h[Print help]' \
      #|'--help[Print help]' \
      #|":: :_nested__subcmd__a__subcmd__b_commands" \
      #|"*::: :->b" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (b)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:nested-a-b-command-$line[1]:"
      #|        case $line[1] in
      #|            (c)
      #|_arguments "${_arguments_options[@]}" : \
      #|'-h[Print help]' \
      #|'--help[Print help]' \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_nested__subcmd__a__subcmd__b__subcmd__help_commands" \
      #|"*::: :->help" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (help)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:nested-a-b-help-command-$line[1]:"
      #|        case $line[1] in
      #|            (c)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_nested__subcmd__a__subcmd__help_commands" \
      #|"*::: :->help" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (help)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:nested-a-help-command-$line[1]:"
      #|        case $line[1] in
      #|            (b)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_nested__subcmd__a__subcmd__help__subcmd__b_commands" \
      #|"*::: :->b" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (b)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:nested-a-help-b-command-$line[1]:"
      #|        case $line[1] in
      #|            (c)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|(d)
      #|_arguments "${_arguments_options[@]}" : \
      #|'-h[Print help]' \
      #|'--help[Print help]' \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_nested__subcmd__help_commands" \
      #|"*::: :->help" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (help)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:nested-help-command-$line[1]:"
      #|        case $line[1] in
      #|            (a)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_nested__subcmd__help__subcmd__a_commands" \
      #|"*::: :->a" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (a)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:nested-help-a-command-$line[1]:"
      #|        case $line[1] in
      #|            (b)
      #|_arguments "${_arguments_options[@]}" : \
      #|":: :_nested__subcmd__help__subcmd__a__subcmd__b_commands" \
      #|"*::: :->b" \
      #|&& ret=0
      #|
      #|    case $state in
      #|    (b)
      #|        words=($line[1] "${words[@]}")
      #|        (( CURRENT += 1 ))
      #|        curcontext="${curcontext%:*:*}:nested-help-a-b-command-$line[1]:"
      #|        case $line[1] in
      #|            (c)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|(d)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|(help)
      #|_arguments "${_arguments_options[@]}" : \
      #|&& ret=0
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|;;
      #|        esac
      #|    ;;
      #|esac
      #|}
      #|
      #|(( $+functions[_nested_commands] )) ||
      #|_nested_commands() {
      #|    local commands; commands=(
      #|'a:A' \
      #|'d:' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'nested commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a_commands] )) ||
      #|_nested__subcmd__a_commands() {
      #|    local commands; commands=(
      #|'b:B' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'nested a commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a__subcmd__b_commands] )) ||
      #|_nested__subcmd__a__subcmd__b_commands() {
      #|    local commands; commands=(
      #|'c:' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'nested a b commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a__subcmd__b__subcmd__c_commands] )) ||
      #|_nested__subcmd__a__subcmd__b__subcmd__c_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'nested a b c commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a__subcmd__b__subcmd__help_commands] )) ||
      #|_nested__subcmd__a__subcmd__b__subcmd__help_commands() {
      #|    local commands; commands=(
      #|'c:' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'nested a b help commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a__subcmd__b__subcmd__help__subcmd__c_commands] )) ||
      #|_nested__subcmd__a__subcmd__b__subcmd__help__subcmd__c_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'nested a b help c commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a__subcmd__b__subcmd__help__subcmd__help_commands] )) ||
      #|_nested__subcmd__a__subcmd__b__subcmd__help__subcmd__help_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'nested a b help help commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a__subcmd__help_commands] )) ||
      #|_nested__subcmd__a__subcmd__help_commands() {
      #|    local commands; commands=(
      #|'b:B' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'nested a help commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a__subcmd__help__subcmd__b_commands] )) ||
      #|_nested__subcmd__a__subcmd__help__subcmd__b_commands() {
      #|    local commands; commands=(
      #|'c:' \
      #|    )
      #|    _describe -t commands 'nested a help b commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a__subcmd__help__subcmd__b__subcmd__c_commands] )) ||
      #|_nested__subcmd__a__subcmd__help__subcmd__b__subcmd__c_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'nested a help b c commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__a__subcmd__help__subcmd__help_commands] )) ||
      #|_nested__subcmd__a__subcmd__help__subcmd__help_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'nested a help help commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__d_commands] )) ||
      #|_nested__subcmd__d_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'nested d commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__help_commands] )) ||
      #|_nested__subcmd__help_commands() {
      #|    local commands; commands=(
      #|'a:A' \
      #|'d:' \
      #|'help:Print this message or the help of the given subcommand(s)' \
      #|    )
      #|    _describe -t commands 'nested help commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__help__subcmd__a_commands] )) ||
      #|_nested__subcmd__help__subcmd__a_commands() {
      #|    local commands; commands=(
      #|'b:B' \
      #|    )
      #|    _describe -t commands 'nested help a commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__help__subcmd__a__subcmd__b_commands] )) ||
      #|_nested__subcmd__help__subcmd__a__subcmd__b_commands() {
      #|    local commands; commands=(
      #|'c:' \
      #|    )
      #|    _describe -t commands 'nested help a b commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__help__subcmd__a__subcmd__b__subcmd__c_commands] )) ||
      #|_nested__subcmd__help__subcmd__a__subcmd__b__subcmd__c_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'nested help a b c commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__help__subcmd__d_commands] )) ||
      #|_nested__subcmd__help__subcmd__d_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'nested help d commands' commands "$@"
      #|}
      #|(( $+functions[_nested__subcmd__help__subcmd__help_commands] )) ||
      #|_nested__subcmd__help__subcmd__help_commands() {
      #|    local commands; commands=()
      #|    _describe -t commands 'nested help help commands' commands "$@"
      #|}
      #|
      #|if [ "$funcstack[1]" = "_nested" ]; then
      #|    _nested "$@"
      #|else
      #|    compdef _nested nested
      #|fi
      #|
    ),
  )
}
