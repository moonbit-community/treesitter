// Expected output: clap_complete 4.6.11's PowerShell generator on the Rust
// equivalent of `unicode_shorts` (`char::is_uppercase` is the Unicode
// Uppercase property, including Other_Uppercase and titlecase exclusion).

///|
fn unicode_shorts() -> @clap.Command {
  @clap.Command::new("app")
  .arg(@clap.Arg::new("a").short('Ä').action(SetTrue).help("Upper A umlaut"))
  .arg(@clap.Arg::new("b").short('ä').action(SetTrue).help("Lower a umlaut"))
  .arg(
    @clap.Arg::new("c")
    .short('Σ')
    .visible_short_alias('ǅ')
    .action(SetTrue)
    .help("Sigma"),
  )
  .arg(
    @clap.Arg::new("d")
    .short('Ⅷ')
    .visible_short_alias('ⓐ')
    .visible_short_alias('Ⓐ')
    .action(SetTrue)
    .help("Other_Uppercase"),
  )
  .arg(@clap.Arg::new("e").short('𝐀').action(SetTrue).help("Math bold"))
}

///|
test "powershell unicode uppercase shorts" {
  inspect(
    @clap_complete.generate(PowerShell, unicode_shorts(), "app"),
    content=(
      #|
      #|using namespace System.Management.Automation
      #|using namespace System.Management.Automation.Language
      #|
      #|Register-ArgumentCompleter -Native -CommandName 'app' -ScriptBlock {
      #|    param($wordToComplete, $commandAst, $cursorPosition)
      #|
      #|    $commandElements = $commandAst.CommandElements
      #|    $command = @(
      #|        'app'
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
      #|        'app' {
      #|            [CompletionResult]::new('-Ä', '-Ä ', [CompletionResultType]::ParameterName, 'Upper A umlaut')
      #|            [CompletionResult]::new('-ä', '-ä', [CompletionResultType]::ParameterName, 'Lower a umlaut')
      #|            [CompletionResult]::new('-Σ', '-Σ ', [CompletionResultType]::ParameterName, 'Sigma')
      #|            [CompletionResult]::new('-ǅ', '-ǅ', [CompletionResultType]::ParameterName, 'Sigma')
      #|            [CompletionResult]::new('-Ⅷ', '-Ⅷ ', [CompletionResultType]::ParameterName, 'Other_Uppercase')
      #|            [CompletionResult]::new('-ⓐ', '-ⓐ', [CompletionResultType]::ParameterName, 'Other_Uppercase')
      #|            [CompletionResult]::new('-Ⓐ', '-Ⓐ ', [CompletionResultType]::ParameterName, 'Other_Uppercase')
      #|            [CompletionResult]::new('-𝐀', '-𝐀 ', [CompletionResultType]::ParameterName, 'Math bold')
      #|            [CompletionResult]::new('-h', '-h', [CompletionResultType]::ParameterName, 'Print help')
      #|            [CompletionResult]::new('--help', '--help', [CompletionResultType]::ParameterName, 'Print help')
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
