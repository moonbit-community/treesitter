// Port of clap_complete 4.6.11 `aot/shells/powershell.rs`.

///|
fn generate_powershell(cmd : @clap.Command, buf : StringBuilder) -> Unit {
  let bin_name = cmd.get_bin_name().unwrap()
  let subcommands_cases = powershell_generate_inner(cmd, "")
  buf.write_string(
    (
      $|
      $|using namespace System.Management.Automation
      $|using namespace System.Management.Automation.Language
      $|
      $|Register-ArgumentCompleter -Native -CommandName '\{bin_name}' -ScriptBlock {
      $|    param($wordToComplete, $commandAst, $cursorPosition)
      $|
      $|    $commandElements = $commandAst.CommandElements
      $|    $command = @(
      $|        '\{bin_name}'
      $|        for ($i = 1; $i -lt $commandElements.Count; $i++) {
      $|            $element = $commandElements[$i]
      $|            if ($element -isnot [StringConstantExpressionAst] -or
      $|                $element.StringConstantType -ne [StringConstantType]::BareWord -or
      $|                $element.Value.StartsWith('-') -or
      $|                $element.Value -eq $wordToComplete) {
      $|                break
      $|        }
      $|        $element.Value
      $|    }) -join ';'
      $|
      $|    $completions = @(switch ($command) {\{subcommands_cases}
      $|    })
      $|
      $|    $completions.Where{ $_.CompletionText -like "$wordToComplete*" } |
      $|        Sort-Object -Property ListItemText
      $|}
      $|
    ),
  )
}

///|
/// Escape string inside single quotes.
fn powershell_escape_string(s : String) -> String {
  s.replace_all(old="'", new="''").replace_all(old="’", new="'’")
}

///|
fn powershell_escape_help(help : String?, data : String) -> String {
  if help is Some(help) && !help.is_empty() {
    return powershell_escape_string(help.replace_all(old="\n", new=" "))
  }
  data
}

///|
fn powershell_generate_inner(
  p : @clap.Command,
  previous_command_name : String,
) -> String {
  let command_names = if previous_command_name.is_empty() {
    [p.get_bin_name().unwrap()]
  } else {
    p
    .get_name_and_visible_aliases()
    .map(name => "\{previous_command_name};\{name}")
  }
  let completions = StringBuilder()
  let preamble = "\n            [CompletionResult]::new("
  for option in p.get_opts() {
    powershell_generate_aliases(completions, preamble, option)
  }
  for flag in flags(p) {
    powershell_generate_aliases(completions, preamble, flag)
  }
  for subcommand in p.get_subcommands() {
    for name in subcommand.get_name_and_visible_aliases() {
      let tooltip = powershell_escape_help(subcommand.get_about(), name)
      completions.write_string(preamble)
      completions.write_string(
        "'\{name}', '\{name}', [CompletionResultType]::ParameterValue, '\{tooltip}')",
      )
    }
  }
  let completions = completions.to_string()
  let subcommands_cases = StringBuilder()
  for command_name in command_names {
    subcommands_cases.write_string(
      (
        $|
        $|        '\{command_name}' {\{completions}
        $|            break
        $|        }
      ),
    )
  }
  for subcommand in p.get_subcommands() {
    for command_name in command_names {
      subcommands_cases.write_string(
        powershell_generate_inner(subcommand, command_name),
      )
    }
  }
  subcommands_cases.to_string()
}

///|
fn powershell_generate_aliases(
  completions : StringBuilder,
  preamble : String,
  arg : @clap.Arg,
) -> Unit {
  if arg.get_short_and_visible_aliases() is Some(aliases) {
    let tooltip = powershell_escape_help(arg.get_help(), aliases[0].to_string())
    for alias in aliases {
      // make PowerShell realize there is a difference between `-s` and `-S`
      let upper = if is_uppercase(alias) { " " } else { "" }
      completions.write_string(
        "\{preamble}'-\{alias}', '-\{alias}\{upper}', [CompletionResultType]::ParameterName, '\{tooltip}')",
      )
    }
  }
  if arg.get_long_and_visible_aliases() is Some(aliases) {
    let tooltip = powershell_escape_help(arg.get_help(), aliases[0])
    for alias in aliases {
      completions.write_string(
        "\{preamble}'--\{alias}', '--\{alias}', [CompletionResultType]::ParameterName, '\{tooltip}')",
      )
    }
  }
}
