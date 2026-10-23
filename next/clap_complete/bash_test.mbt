// Expected output: clap_complete's Bash generator on the Rust
// equivalents of the commands in commands_test.mbt.

///|
test "bash my-app" {
  inspect(
    @clap_complete.generate(Bash, my_app(), "my-app"),
    content=(
      #|_my__app() {
      #|    local i cur prev opts cmd
      #|    COMPREPLY=()
      #|    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      #|        cur="$2"
      #|    else
      #|        cur="${COMP_WORDS[COMP_CWORD]}"
      #|    fi
      #|    prev="$3"
      #|    cmd=""
      #|    opts=""
      #|
      #|    for i in "${COMP_WORDS[@]:0:COMP_CWORD}"
      #|    do
      #|        case "${cmd},${i}" in
      #|            ",$1")
      #|                cmd="my__app"
      #|                ;;
      #|            my__app,b)
      #|                cmd="my__app__subcmd__build"
      #|                ;;
      #|            my__app,build)
      #|                cmd="my__app__subcmd__build"
      #|                ;;
      #|            my__app,help)
      #|                cmd="my__app__subcmd__help"
      #|                ;;
      #|            my__app,hidden)
      #|                cmd="my__app__subcmd__hidden"
      #|                ;;
      #|            my__app,test-all)
      #|                cmd="my__app__subcmd__test__subcmd__all"
      #|                ;;
      #|            my__app__subcmd__build,clean)
      #|                cmd="my__app__subcmd__build__subcmd__clean"
      #|                ;;
      #|            my__app__subcmd__build,help)
      #|                cmd="my__app__subcmd__build__subcmd__help"
      #|                ;;
      #|            my__app__subcmd__build__subcmd__help,clean)
      #|                cmd="my__app__subcmd__build__subcmd__help__subcmd__clean"
      #|                ;;
      #|            my__app__subcmd__build__subcmd__help,help)
      #|                cmd="my__app__subcmd__build__subcmd__help__subcmd__help"
      #|                ;;
      #|            my__app__subcmd__help,build)
      #|                cmd="my__app__subcmd__help__subcmd__build"
      #|                ;;
      #|            my__app__subcmd__help,help)
      #|                cmd="my__app__subcmd__help__subcmd__help"
      #|                ;;
      #|            my__app__subcmd__help,hidden)
      #|                cmd="my__app__subcmd__help__subcmd__hidden"
      #|                ;;
      #|            my__app__subcmd__help,test-all)
      #|                cmd="my__app__subcmd__help__subcmd__test__subcmd__all"
      #|                ;;
      #|            my__app__subcmd__help__subcmd__build,clean)
      #|                cmd="my__app__subcmd__help__subcmd__build__subcmd__clean"
      #|                ;;
      #|            *)
      #|                ;;
      #|        esac
      #|    done
      #|
      #|    case "${cmd}" in
      #|        my__app)
      #|            opts="-v -c -O -o -s -q -h -V --verbose --config --color --mode --output --out --name --file --silent --quiet --secret --help --version build b test-all hidden help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 1 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                --config)
      #|                    COMPREPLY=($(compgen -f "${cur}"))
      #|                    return 0
      #|                    ;;
      #|                -c)
      #|                    COMPREPLY=($(compgen -f "${cur}"))
      #|                    return 0
      #|                    ;;
      #|                --color)
      #|                    COMPREPLY=($(compgen -W "always never" -- "${cur}"))
      #|                    return 0
      #|                    ;;
      #|                --mode)
      #|                    COMPREPLY=($(compgen -W "fast slow mode" -- "${cur}"))
      #|                    return 0
      #|                    ;;
      #|                --out)
      #|                    COMPREPLY=()
      #|                    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      #|                        compopt -o plusdirs
      #|                    fi
      #|                    return 0
      #|                    ;;
      #|                --output)
      #|                    COMPREPLY=()
      #|                    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      #|                        compopt -o plusdirs
      #|                    fi
      #|                    return 0
      #|                    ;;
      #|                -o)
      #|                    COMPREPLY=()
      #|                    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      #|                        compopt -o plusdirs
      #|                    fi
      #|                    return 0
      #|                    ;;
      #|                -O)
      #|                    COMPREPLY=()
      #|                    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      #|                        compopt -o plusdirs
      #|                    fi
      #|                    return 0
      #|                    ;;
      #|                --name)
      #|                    COMPREPLY=("${cur}")
      #|                    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      #|                        compopt -o nospace
      #|                    fi
      #|                    return 0
      #|                    ;;
      #|                --file)
      #|                    local oldifs
      #|                    if [ -n "${IFS+x}" ]; then
      #|                        oldifs="$IFS"
      #|                    fi
      #|                    IFS=$'\n'
      #|                    COMPREPLY=($(compgen -f "${cur}"))
      #|                    if [ -n "${oldifs+x}" ]; then
      #|                        IFS="$oldifs"
      #|                    fi
      #|                    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      #|                        compopt -o filenames
      #|                    fi
      #|                    return 0
      #|                    ;;
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__build)
      #|            opts="-h --release --help x86 arm clean help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 2 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__build__subcmd__clean)
      #|            opts="-h --help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__build__subcmd__help)
      #|            opts="clean help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__build__subcmd__help__subcmd__clean)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 4 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__build__subcmd__help__subcmd__help)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 4 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__help)
      #|            opts="build test-all hidden help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 2 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__help__subcmd__build)
      #|            opts="clean"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__help__subcmd__build__subcmd__clean)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 4 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__help__subcmd__help)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__help__subcmd__hidden)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__help__subcmd__test__subcmd__all)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__hidden)
      #|            opts="-h --help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 2 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        my__subcmd__app__subcmd__test__subcmd__all)
      #|            opts="-j -h --help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 2 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                -j)
      #|                    COMPREPLY=($(compgen -f "${cur}"))
      #|                    return 0
      #|                    ;;
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|    esac
      #|}
      #|
      #|if [[ "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -ge 4 || "${BASH_VERSINFO[0]}" -gt 4 ]]; then
      #|    complete -F _my__app -o nosort -o bashdefault -o default my-app
      #|else
      #|    complete -F _my__app -o bashdefault -o default my-app
      #|fi
      #|
    ),
  )
}

///|
test "bash nested" {
  inspect(
    @clap_complete.generate(Bash, nested(), "nested"),
    content=(
      #|_nested() {
      #|    local i cur prev opts cmd
      #|    COMPREPLY=()
      #|    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
      #|        cur="$2"
      #|    else
      #|        cur="${COMP_WORDS[COMP_CWORD]}"
      #|    fi
      #|    prev="$3"
      #|    cmd=""
      #|    opts=""
      #|
      #|    for i in "${COMP_WORDS[@]:0:COMP_CWORD}"
      #|    do
      #|        case "${cmd},${i}" in
      #|            ",$1")
      #|                cmd="nested"
      #|                ;;
      #|            nested,a)
      #|                cmd="nested__subcmd__a"
      #|                ;;
      #|            nested,d)
      #|                cmd="nested__subcmd__d"
      #|                ;;
      #|            nested,help)
      #|                cmd="nested__subcmd__help"
      #|                ;;
      #|            nested__subcmd__a,b)
      #|                cmd="nested__subcmd__a__subcmd__b"
      #|                ;;
      #|            nested__subcmd__a,help)
      #|                cmd="nested__subcmd__a__subcmd__help"
      #|                ;;
      #|            nested__subcmd__a__subcmd__b,c)
      #|                cmd="nested__subcmd__a__subcmd__b__subcmd__c"
      #|                ;;
      #|            nested__subcmd__a__subcmd__b,help)
      #|                cmd="nested__subcmd__a__subcmd__b__subcmd__help"
      #|                ;;
      #|            nested__subcmd__a__subcmd__b__subcmd__help,c)
      #|                cmd="nested__subcmd__a__subcmd__b__subcmd__help__subcmd__c"
      #|                ;;
      #|            nested__subcmd__a__subcmd__b__subcmd__help,help)
      #|                cmd="nested__subcmd__a__subcmd__b__subcmd__help__subcmd__help"
      #|                ;;
      #|            nested__subcmd__a__subcmd__help,b)
      #|                cmd="nested__subcmd__a__subcmd__help__subcmd__b"
      #|                ;;
      #|            nested__subcmd__a__subcmd__help,help)
      #|                cmd="nested__subcmd__a__subcmd__help__subcmd__help"
      #|                ;;
      #|            nested__subcmd__a__subcmd__help__subcmd__b,c)
      #|                cmd="nested__subcmd__a__subcmd__help__subcmd__b__subcmd__c"
      #|                ;;
      #|            nested__subcmd__help,a)
      #|                cmd="nested__subcmd__help__subcmd__a"
      #|                ;;
      #|            nested__subcmd__help,d)
      #|                cmd="nested__subcmd__help__subcmd__d"
      #|                ;;
      #|            nested__subcmd__help,help)
      #|                cmd="nested__subcmd__help__subcmd__help"
      #|                ;;
      #|            nested__subcmd__help__subcmd__a,b)
      #|                cmd="nested__subcmd__help__subcmd__a__subcmd__b"
      #|                ;;
      #|            nested__subcmd__help__subcmd__a__subcmd__b,c)
      #|                cmd="nested__subcmd__help__subcmd__a__subcmd__b__subcmd__c"
      #|                ;;
      #|            *)
      #|                ;;
      #|        esac
      #|    done
      #|
      #|    case "${cmd}" in
      #|        nested)
      #|            opts="-h --help a d help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 1 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a)
      #|            opts="-h --help b help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 2 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a__subcmd__b)
      #|            opts="-h --help c help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a__subcmd__b__subcmd__c)
      #|            opts="-h --help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 4 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a__subcmd__b__subcmd__help)
      #|            opts="c help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 4 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a__subcmd__b__subcmd__help__subcmd__c)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 5 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a__subcmd__b__subcmd__help__subcmd__help)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 5 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a__subcmd__help)
      #|            opts="b help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a__subcmd__help__subcmd__b)
      #|            opts="c"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 4 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a__subcmd__help__subcmd__b__subcmd__c)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 5 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__a__subcmd__help__subcmd__help)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 4 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__d)
      #|            opts="-h --help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 2 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__help)
      #|            opts="a d help"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 2 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__help__subcmd__a)
      #|            opts="b"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__help__subcmd__a__subcmd__b)
      #|            opts="c"
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 4 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__help__subcmd__a__subcmd__b__subcmd__c)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 5 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__help__subcmd__d)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|        nested__subcmd__help__subcmd__help)
      #|            opts=""
      #|            if [[ ${cur} == -* || ${COMP_CWORD} -eq 3 ]] ; then
      #|                COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|                return 0
      #|            fi
      #|            case "${prev}" in
      #|                *)
      #|                    COMPREPLY=()
      #|                    ;;
      #|            esac
      #|            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
      #|            return 0
      #|            ;;
      #|    esac
      #|}
      #|
      #|if [[ "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -ge 4 || "${BASH_VERSINFO[0]}" -gt 4 ]]; then
      #|    complete -F _nested -o nosort -o bashdefault -o default nested
      #|else
      #|    complete -F _nested -o bashdefault -o default nested
      #|fi
      #|
    ),
  )
}
