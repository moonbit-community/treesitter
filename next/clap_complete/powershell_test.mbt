// Expected output: clap_complete's PowerShell generator on the Rust
// equivalents of the commands in commands_test.mbt.

///|
test "powershell my-app" {
  inspect(
    @clap_complete.generate(PowerShell, my_app(), "my-app"),
    content=(
      #|
      #|using namespace System.Management.Automation
      #|using namespace System.Management.Automation.Language
      #|
      #|Register-ArgumentCompleter -Native -CommandName 'my-app' -ScriptBlock {
      #|    param($wordToComplete, $commandAst, $cursorPosition)
      #|
      #|    $commandElements = $commandAst.CommandElements
      #|    $command = @(
      #|        'my-app'
      #|        for ($i = 1; $i -lt $commandElements.Count; $i++) {
      #|            $element = $commandElements[$i]
      #|            if ($element -isnot [StringConstantExpressionAst] -or
      #|                $element.StringConstantType -ne [StringConstantType]::BareWord -or
      #|                $element.Value.StartsWith('-') -or
      #|                $element.Value -eq $wordToComplete) {
      #|                break
      #|        }
      #|        $element.Value
      #|    }) -join ';'
      #|
      #|    $completions = @(switch ($command) {
      #|        'my-app' {
      #|            [CompletionResult]::new('-c', '-c', [CompletionResultType]::ParameterName, 'Config file: it''s `$HOME`')
      #|            [CompletionResult]::new('--config', '--config', [CompletionResultType]::ParameterName, 'Config file: it''s `$HOME`')
      #|            [CompletionResult]::new('--color', '--color', [CompletionResultType]::ParameterName, 'When to color')
      #|            [CompletionResult]::new('--mode', '--mode', [CompletionResultType]::ParameterName, 'mode')
      #|            [CompletionResult]::new('-o', '-o', [CompletionResultType]::ParameterName, 'Output directory')
      #|            [CompletionResult]::new('-O', '-O ', [CompletionResultType]::ParameterName, 'Output directory')
      #|            [CompletionResult]::new('--out', '--out', [CompletionResultType]::ParameterName, 'Output directory')
      #|            [CompletionResult]::new('--output', '--output', [CompletionResultType]::ParameterName, 'Output directory')
      #|            [CompletionResult]::new('--name', '--name', [CompletionResultType]::ParameterName, 'A name')
      #|            [CompletionResult]::new('--file', '--file', [CompletionResultType]::ParameterName, 'Two files')
      #|            [CompletionResult]::new('-v', '-v', [CompletionResultType]::ParameterName, 'Verbosity [level]')
      #|            [CompletionResult]::new('--verbose', '--verbose', [CompletionResultType]::ParameterName, 'Verbosity [level]')
      #|            [CompletionResult]::new('-q', '-q', [CompletionResultType]::ParameterName, 'Be quiet, please')
      #|            [CompletionResult]::new('-s', '-s', [CompletionResultType]::ParameterName, 'Be quiet, please')
      #|            [CompletionResult]::new('--quiet', '--quiet', [CompletionResultType]::ParameterName, 'Be quiet, please')
      #|            [CompletionResult]::new('--silent', '--silent', [CompletionResultType]::ParameterName, 'Be quiet, please')
      #|            [CompletionResult]::new('--secret', '--secret', [CompletionResultType]::ParameterName, 'secret')
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
      #|            [CompletionResult]::new('-V', '-V ', [CompletionResultType]::ParameterName, 'Print version')
      #|            [CompletionResult]::new('--version', '--version', [CompletionResultType]::ParameterName, 'Print version')
      #|            [CompletionResult]::new('build', 'build', [CompletionResultType]::ParameterValue, 'Build it')
      #|            [CompletionResult]::new('b', 'b', [CompletionResultType]::ParameterValue, 'Build it')
      #|            [CompletionResult]::new('test-all', 'test-all', [CompletionResultType]::ParameterValue, 'Run ''all'' tests')
      #|            [CompletionResult]::new('hidden', 'hidden', [CompletionResultType]::ParameterValue, 'hidden')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'my-app;build' {
      #|            [CompletionResult]::new('--release', '--release', [CompletionResultType]::ParameterName, 'Release mode')
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
      #|            [CompletionResult]::new('clean', 'clean', [CompletionResultType]::ParameterValue, 'Clean up')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'my-app;b' {
      #|            [CompletionResult]::new('--release', '--release', [CompletionResultType]::ParameterName, 'Release mode')
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help (see more with ''--help'')')
      #|            [CompletionResult]::new('clean', 'clean', [CompletionResultType]::ParameterValue, 'Clean up')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'my-app;build;clean' {
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
      #|            break
      #|        }
      #|        'my-app;b;clean' {
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
      #|            break
      #|        }
      #|        'my-app;build;help' {
      #|            [CompletionResult]::new('clean', 'clean', [CompletionResultType]::ParameterValue, 'Clean up')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'my-app;build;help;clean' {
      #|            break
      #|        }
      #|        'my-app;build;help;help' {
      #|            break
      #|        }
      #|        'my-app;b;help' {
      #|            [CompletionResult]::new('clean', 'clean', [CompletionResultType]::ParameterValue, 'Clean up')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'my-app;b;help;clean' {
      #|            break
      #|        }
      #|        'my-app;b;help;help' {
      #|            break
      #|        }
      #|        'my-app;test-all' {
      #|            [CompletionResult]::new('-j', '-j', [CompletionResultType]::ParameterName, 'Jobs')
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
      #|            break
      #|        }
      #|        'my-app;hidden' {
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
      #|            break
      #|        }
      #|        'my-app;help' {
      #|            [CompletionResult]::new('build', 'build', [CompletionResultType]::ParameterValue, 'Build it')
      #|            [CompletionResult]::new('test-all', 'test-all', [CompletionResultType]::ParameterValue, 'Run ''all'' tests')
      #|            [CompletionResult]::new('hidden', 'hidden', [CompletionResultType]::ParameterValue, 'hidden')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'my-app;help;build' {
      #|            [CompletionResult]::new('clean', 'clean', [CompletionResultType]::ParameterValue, 'Clean up')
      #|            break
      #|        }
      #|        'my-app;help;build;clean' {
      #|            break
      #|        }
      #|        'my-app;help;test-all' {
      #|            break
      #|        }
      #|        'my-app;help;hidden' {
      #|            break
      #|        }
      #|        'my-app;help;help' {
      #|            break
      #|        }
      #|    })
      #|
      #|    $completions.Where{ $_.CompletionText -like "$wordToComplete*" } |
      #|        Sort-Object -Property ListItemText
      #|}
      #|
    ),
  )
}

///|
test "powershell nested" {
  inspect(
    @clap_complete.generate(PowerShell, nested(), "nested"),
    content=(
      #|
      #|using namespace System.Management.Automation
      #|using namespace System.Management.Automation.Language
      #|
      #|Register-ArgumentCompleter -Native -CommandName 'nested' -ScriptBlock {
      #|    param($wordToComplete, $commandAst, $cursorPosition)
      #|
      #|    $commandElements = $commandAst.CommandElements
      #|    $command = @(
      #|        'nested'
      #|        for ($i = 1; $i -lt $commandElements.Count; $i++) {
      #|            $element = $commandElements[$i]
      #|            if ($element -isnot [StringConstantExpressionAst] -or
      #|                $element.StringConstantType -ne [StringConstantType]::BareWord -or
      #|                $element.Value.StartsWith('-') -or
      #|                $element.Value -eq $wordToComplete) {
      #|                break
      #|        }
      #|        $element.Value
      #|    }) -join ';'
      #|
      #|    $completions = @(switch ($command) {
      #|        'nested' {
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('a', 'a', [CompletionResultType]::ParameterValue, 'A')
      #|            [CompletionResult]::new('d', 'd', [CompletionResultType]::ParameterValue, 'd')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'nested;a' {
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('b', 'b', [CompletionResultType]::ParameterValue, 'B')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'nested;a;b' {
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('c', 'c', [CompletionResultType]::ParameterValue, 'c')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'nested;a;b;c' {
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
      #|            break
      #|        }
      #|        'nested;a;b;help' {
      #|            [CompletionResult]::new('c', 'c', [CompletionResultType]::ParameterValue, 'c')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'nested;a;b;help;c' {
      #|            break
      #|        }
      #|        'nested;a;b;help;help' {
      #|            break
      #|        }
      #|        'nested;a;help' {
      #|            [CompletionResult]::new('b', 'b', [CompletionResultType]::ParameterValue, 'B')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'nested;a;help;b' {
      #|            [CompletionResult]::new('c', 'c', [CompletionResultType]::ParameterValue, 'c')
      #|            break
      #|        }
      #|        'nested;a;help;b;c' {
      #|            break
      #|        }
      #|        'nested;a;help;help' {
      #|            break
      #|        }
      #|        'nested;d' {
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
      #|            break
      #|        }
      #|        'nested;help' {
      #|            [CompletionResult]::new('a', 'a', [CompletionResultType]::ParameterValue, 'A')
      #|            [CompletionResult]::new('d', 'd', [CompletionResultType]::ParameterValue, 'd')
      #|            [CompletionResult]::new('help', 'help', [CompletionResultType]::ParameterValue, 'Print this message or the help of the given subcommand(s)')
      #|            break
      #|        }
      #|        'nested;help;a' {
      #|            [CompletionResult]::new('b', 'b', [CompletionResultType]::ParameterValue, 'B')
      #|            break
      #|        }
      #|        'nested;help;a;b' {
      #|            [CompletionResult]::new('c', 'c', [CompletionResultType]::ParameterValue, 'c')
      #|            break
      #|        }
      #|        'nested;help;a;b;c' {
      #|            break
      #|        }
      #|        'nested;help;d' {
      #|            break
      #|        }
      #|        'nested;help;help' {
      #|            break
      #|        }
      #|    })
      #|
      #|    $completions.Where{ $_.CompletionText -like "$wordToComplete*" } |
      #|        Sort-Object -Property ListItemText
      #|}
      #|
    ),
  )
}
