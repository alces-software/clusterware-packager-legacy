################################################################################
##
## Alces HPC Software Stack - Symphony shell configuration
## Copyright (c) 2008-2014 Alces Software Ltd
##
################################################################################
if ( $uid != "0" ) then
    if ( "${alces_MODE}" == "system" && ! -f "$HOME/.alces/.alces-suite" ) then
	/opt/clusterware/bin/alces config install
    endif
    foreach a ( modules modulerc modulespath )
	if ( ! -f "$HOME/.$a" ) then
	    ln -s ".alces/etc/$a" "$HOME/.$a"
	endif
    end
else
    # we are root, so must be using a system-wide installation
    foreach a ( modules modulerc modulespath )
	if ( ! -f "$HOME/.$a" ) then
	    cp /opt/clusterware/etc/skel/$a "$HOME/.$a"
	endif
    end
endif

set exec_prefix='${alces_PATH}/opt/${alces_OS}/Modules/bin'

set prefix=""
set postfix=""

if ( $?histchars ) then
  set histchar = `echo $histchars | cut -c1`
  set _histchars = $histchars

  set prefix  = 'unset histchars;'
  set postfix = 'set histchars = $_histchars;'
else
  set histchar = \!
endif

if ($?prompt) then
  set prefix  = "$prefix"'set _prompt="$prompt";set prompt="";'
  set postfix = "$postfix"'set prompt="$_prompt";unset _prompt;'
endif

if ($?noglob) then
  set prefix  = "$prefix""set noglob;"
  set postfix = "$postfix""unset noglob;"
endif
set postfix = "set _exit="'$status'"; $postfix; test 0 = "'$_exit;'

alias module $prefix'eval `'$exec_prefix'/modulecmd '$alces_SHELL' '$histchar'*`; '$postfix

if (! $?MODULEPATH ) then
    if ( "${alces_MODE}" == "system" ) then
      setenv MODULEPATH `sed -n 's/[      #].*$//; /./H; $ { x; s/^\n//; s/\n/:/g; p; }' /opt/clusterware/etc/modulespath`
    else
      setenv MODULEPATH ""
    endif
    if ( -f "$HOME/.modulespath" ) then
      set usermodulepath = `sed -n 's/[     #].*$//; /./H; $ { x; s/^\n//; s/\n/:/g; p; }' "$HOME/.modulespath"`
      setenv MODULEPATH "$usermodulepath":"$MODULEPATH"
    endif
endif

if (! $?LOADEDMODULES ) then
  setenv LOADEDMODULES ""
endif

alias mod 'module'

if (! $?alces_MODULES_RECORD ) then
  setenv alces_MODULES_RECORD 0
endif

alias alces_silence_modules 'setenv alces_MODULES_VERBOSE_ORIGINAL "$alces_MODULES_VERBOSE"; setenv alces_MODULES_VERBOSE 0; setenv alces_MODULES_RECORD_ORIGINAL "$alces_MODULES_RECORD"; setenv alces_MODULES_RECORD 0'
alias alces_desilence_modules 'setenv alces_MODULES_VERBOSE "$alces_MODULES_VERBOSE_ORIGINAL"; unsetenv alces_MODULES_VERBOSE_ORIGINAL; setenv alces_RECORD_VERBOSE "$alces_MODULES_RECORD_ORIGINAL"; unsetenv alces_MODULES_RECORD_ORIGINAL'

if (! $?alces_MODULES_VERBOSE ) then
    setenv alces_MODULES_VERBOSE 1
endif

#source modules file from home dir
if ( -r ~/.modules ) then
  source ~/.modules
endif

unset exec_prefix
unset prefix
unset postfix
