// Expected output: clap_complete's Elvish generator on the Rust
// equivalents of the commands in commands_test.mbt.

///|
test "elvish my-app" {
  inspect(
    @clap_complete.generate(Elvish, my_app(), "my-app"),
    content=(
      #|
      #|use builtin;
      #|use str;
      #|
      #|set edit:completion:arg-completer[my-app] = {|@words|
      #|    fn spaces {|n|
      #|        builtin:repeat $n ' ' | str:join ''
      #|    }
      #|    fn cand {|text desc|
      #|        edit:complex-candidate $text &display=$text' '(spaces (- 14 (wcswidth $text)))$desc
      #|    }
      #|    var command = 'my-app'
      #|    for word $words[1..-1] {
      #|        if (str:has-prefix $word '-') {
      #|            break
      #|        }
      #|        set command = $command';'$word
      #|    }
      #|    var completions = [
      #|        &'my-app'= {
      #|            cand -c 'Config file: it''s `$HOME`'
      #|            cand --config 'Config file: it''s `$HOME`'
      #|            cand --color 'When to color'
      #|            cand --mode 'mode'
      #|            cand -o 'Output directory'
      #|            cand -O 'Output directory'
      #|            cand --out 'Output directory'
      #|            cand --output 'Output directory'
      #|            cand --name 'A name'
      #|            cand --file 'Two files'
      #|            cand -v 'Verbosity [level]'
      #|            cand --verbose 'Verbosity [level]'
      #|            cand -q 'Be quiet, please'
      #|            cand -s 'Be quiet, please'
      #|            cand --quiet 'Be quiet, please'
      #|            cand --silent 'Be quiet, please'
      #|            cand --secret 'secret'
      #|            cand -h 'Print help (see more with ''--help'')'
      #|            cand --help 'Print help (see more with ''--help'')'
      #|            cand -V 'Print version'
      #|            cand --version 'Print version'
      #|            cand build 'Build it'
      #|            cand b 'Build it'
      #|            cand test-all 'Run ''all'' tests'
      #|            cand hidden 'hidden'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'my-app;build'= {
      #|            cand --release 'Release mode'
      #|            cand -h 'Print help (see more with ''--help'')'
      #|            cand --help 'Print help (see more with ''--help'')'
      #|            cand clean 'Clean up'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'my-app;b'= {
      #|            cand --release 'Release mode'
      #|            cand -h 'Print help (see more with ''--help'')'
      #|            cand --help 'Print help (see more with ''--help'')'
      #|            cand clean 'Clean up'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'my-app;build;clean'= {
      #|            cand -h 'Print help'
      #|            cand --help 'Print help'
      #|        }
      #|        &'my-app;b;clean'= {
      #|            cand -h 'Print help'
      #|            cand --help 'Print help'
      #|        }
      #|        &'my-app;build;help'= {
      #|            cand clean 'Clean up'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'my-app;build;help;clean'= {
      #|        }
      #|        &'my-app;build;help;help'= {
      #|        }
      #|        &'my-app;b;help'= {
      #|            cand clean 'Clean up'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'my-app;b;help;clean'= {
      #|        }
      #|        &'my-app;b;help;help'= {
      #|        }
      #|        &'my-app;test-all'= {
      #|            cand -j 'Jobs'
      #|            cand -h 'Print help'
      #|            cand --help 'Print help'
      #|        }
      #|        &'my-app;hidden'= {
      #|            cand -h 'Print help'
      #|            cand --help 'Print help'
      #|        }
      #|        &'my-app;help'= {
      #|            cand build 'Build it'
      #|            cand test-all 'Run ''all'' tests'
      #|            cand hidden 'hidden'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'my-app;help;build'= {
      #|            cand clean 'Clean up'
      #|        }
      #|        &'my-app;help;build;clean'= {
      #|        }
      #|        &'my-app;help;test-all'= {
      #|        }
      #|        &'my-app;help;hidden'= {
      #|        }
      #|        &'my-app;help;help'= {
      #|        }
      #|    ]
      #|    $completions[$command]
      #|}
      #|
    ),
  )
}

///|
test "elvish nested" {
  inspect(
    @clap_complete.generate(Elvish, nested(), "nested"),
    content=(
      #|
      #|use builtin;
      #|use str;
      #|
      #|set edit:completion:arg-completer[nested] = {|@words|
      #|    fn spaces {|n|
      #|        builtin:repeat $n ' ' | str:join ''
      #|    }
      #|    fn cand {|text desc|
      #|        edit:complex-candidate $text &display=$text' '(spaces (- 14 (wcswidth $text)))$desc
      #|    }
      #|    var command = 'nested'
      #|    for word $words[1..-1] {
      #|        if (str:has-prefix $word '-') {
      #|            break
      #|        }
      #|        set command = $command';'$word
      #|    }
      #|    var completions = [
      #|        &'nested'= {
      #|            cand -h 'Print help'
      #|            cand --help 'Print help'
      #|            cand a 'A'
      #|            cand d 'd'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'nested;a'= {
      #|            cand -h 'Print help'
      #|            cand --help 'Print help'
      #|            cand b 'B'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'nested;a;b'= {
      #|            cand -h 'Print help'
      #|            cand --help 'Print help'
      #|            cand c 'c'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'nested;a;b;c'= {
      #|            cand -h 'Print help'
      #|            cand --help 'Print help'
      #|        }
      #|        &'nested;a;b;help'= {
      #|            cand c 'c'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'nested;a;b;help;c'= {
      #|        }
      #|        &'nested;a;b;help;help'= {
      #|        }
      #|        &'nested;a;help'= {
      #|            cand b 'B'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'nested;a;help;b'= {
      #|            cand c 'c'
      #|        }
      #|        &'nested;a;help;b;c'= {
      #|        }
      #|        &'nested;a;help;help'= {
      #|        }
      #|        &'nested;d'= {
      #|            cand -h 'Print help'
      #|            cand --help 'Print help'
      #|        }
      #|        &'nested;help'= {
      #|            cand a 'A'
      #|            cand d 'd'
      #|            cand help 'Print this message or the help of the given subcommand(s)'
      #|        }
      #|        &'nested;help;a'= {
      #|            cand b 'B'
      #|        }
      #|        &'nested;help;a;b'= {
      #|            cand c 'c'
      #|        }
      #|        &'nested;help;a;b;c'= {
      #|        }
      #|        &'nested;help;d'= {
      #|        }
      #|        &'nested;help;help'= {
      #|        }
      #|    ]
      #|    $completions[$command]
      #|}
      #|
    ),
  )
}
