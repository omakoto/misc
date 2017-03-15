# The MIT License (MIT)
#
# Copyright (c) 2015 Makoto Onuki
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# #
# Usage: source go-completion.bash

# Update this script.
go_complete_update() {
  curl "https://raw.githubusercontent.com/omakoto/go-completion.bash/master/go-completion.bash" > \
      ${BASH_SOURCE[0]}
}

_go_complete() {
  local -A _go_flags
  local _go_build_flags="-a -n -p -race -v -work -x -cclfags -compiler -gccgoflags -gcflags -installsuffix -ldflags -tags"
  local _go_test_flags="-bench -benchmem -benchtime -blockprofile -blockprofilerate -cover -covermode -coverpkg -coverprofile -cpu -cpuprofile -memprofile -memprofilerate -outputdir -parallel -run -short -timeout -v"

  local cmd="${COMP_WORDS[0]}"
  local sub="${COMP_WORDS[1]}"
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"

  local cand=""
  case "$prev" in
    go|goapp)
      cand="build clean env fix fmt get install list run test tool version vet help"
      if [ "$cmd" = "goapp" ]; then
        cand="$cand serve deploy"
      fi
      ;;
    help)
      cand="build clean env fix fmt generate get install list run test tool version vet c filetype gopath importpath packages testflag testfunc"
      if [ "$cmd" = "goapp" ]; then
        cand="$cand serve deploy"
      fi
      ;;
    *)
      case "$cur" in
        -*)
          case "$sub" in
            build)    cand="-o -i ${_go_build_flags}" ;;
            clean)    cand="-i -r -n -x ${_go_build_flags}" ;;
            fmt)      cand="-n -x" ;;
            generate) cand="-run" ;;
            get)      cand="-d -f -fix -t -u ${_go_build_flags}" ;;
            install)  cand="${_go_build_flags}" ;;
            list)     cand="-e -f -json ${_go_build_flags}" ;;
            run)      cand="-exec ${_go_build_flags}" ;;
            test)     cand="-i -c -exec -o ${_go_build_flags} ${_go_test_flags}" ;;
            tool)     cand="-n" ;;
            vet)      cand="-n -x" ;;
            serve)    cand="-host -port -admin_port -clear_datastore" ;;
            deploy)   cand="-application -version -oauth" ;;
          esac
          ;;
      esac
      ;;
  esac
  if [ "x$cand" = "x" ] ; then
    COMPREPLY=($(compgen -f -- ${cur}))
  else
    COMPREPLY=($(compgen -W "$cand" -- ${cur}))
  fi
}

_godoc_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"

  local cand=""
  case "$cur" in
    -*)
      cand="-v -q -src -tabwidth -timestamps -index -index_files -index_throttle -links -write_index -index_files -maxresults -notes -html -goroot -http -server -analysis -templates -url -zip"
      ;;
  esac
  if [ "x$cand" = "x" ] ; then
    COMPREPLY=($(compgen -f -- ${cur}))
  else
    COMPREPLY=($(compgen -W "$cand" -- ${cur}))
  fi
}

complete -o filenames -o bashdefault -F _go_complete go
complete -o filenames -o bashdefault -F _go_complete goapp
complete -o filenames -o bashdefault -F _godoc_complete godoc
