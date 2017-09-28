. <( exec ruby -wx "${BASH_SOURCE[0]}" -i adb2 )
: <<__END_RUBY_CODE__
#!ruby

=begin

# Install
. <(~/cbin/misc/completer-adb.rb)

echo | ruby -x completer-adb4.rb  2 adb
echo | ruby -x completer-adb4.rb  2 adb -s
echo | ruby -x completer-adb4.rb  3 adb -s SE
echo | ruby -x completer-adb4.rb  4 adb -s serial --

echo | ruby -x completer-adb4.rb  2 adb pull

echo | ruby -x completer-adb4.rb  2 adb uninstall
echo | ruby -x completer-adb4.rb  3 adb uninstall -k

=end

require_relative "completer"
using CompleterRefinements

TESTING = ENV["ADB_TEST_COMP"] == "1"

Completer.define do
  def run_command(command)
    debug {"Executing: #{command}"}
    out = ENV['ADB_MOCK_OUT'] || %x(#{command})
    debug {"Output: <<EOF\n#{out}\nEOF"}
    return out || ''
  end

  def take_device_serial()
    lazy do
      ret = []
      run_command(%(adb devices)).split(/\n/).each do |l|
        serial, type = l.split(/\s+/, 2)
        (ret << serial) if type == "device"
      end
      debug {"Serial(s): #{ret.inspect}"}
      ret
    end
  end

  def take_package()
    lazy { run_command(%(adb shell pm list packages 2>/dev/null)).split(/\n/).map {|x| x.sub(/^package\:/, "")} }
  end

  def take_device_file()
    lazy do
      w = word
      w = "/" if w == "" || w == nil
      run_command(%(adb shell ls -pd1 #{shescape w}'* 2>/dev/null')).split(/\n/).map{|x| x + "\r"}
    end
  end

  def take_command()
    lazy { run_command(%(adb shell 'for n in ${PATH//:/ } ; do ls "$n" ; done 2>/dev/null')).split(/\n/) }
  end

  def take_service()
    lazy { run_command(%(adb shell dumpsys -l 2>/dev/null)).split(/\n/)[1..-1].map{|x| x.strip} }
  end

  def main()
    for_arg(/^-/) do
      maybe %w(-a -d -e -H -P)
      maybe "-s", take_device_serial # maybe really should do "next". See the broken test *1.
      maybe "-s2", take_device_serial, take_device_serial
      maybe "-s3", take_device_serial, take_device_serial, take_device_serial
      maybe "-L", []

      if TESTING
        maybe %w(-f --flags), take_file
        maybe %w(--color --colors), %w(always never auto)
        maybe "--" do
          for_break
        end
      end
      maybe(//) do # If nothing above matched, break.
        for_break
      end
    end

    maybe %w(devices help version root unroot reboot-bootloader usb get-state get-serialno
        get-devpath start-server kill-server wait-for-device remount) do
      return
    end

    maybe %w(install install-multiple) do # Do implies next_word.
      for_arg(/^-/) do
        maybe %w(-a -d -e -H -P)
        maybe(//) do # If nothing above matched, break.
          for_break
        end
      end
      next_word_must take_file
      return
    end
    maybe "uninstall" do
      maybe %w(-k)
      next_word_must take_package
    end
    maybe "push" do
      next_word_must take_file, take_device_file
    end
    maybe "pull" do
      next_word_must take_device_file
      next_word_must take_file
    end
    # maybe "reboot" do
    #   maybe %w(bootloader recovery sideload sideload-auto-reboot) do
    #     finish
    #   end
    # end
    # maybe "logcat" do
    #   # TODO
    # end
    # maybe "shell" do
    #   maybe "am" do
    #     am
    #   end
    #   maybe "pm" do
    #     pm
    #   end
    #   maybe "cmd" do
    #     cmd
    #   end
    #   maybe "dumpsys" do
    #     dumpsys
    #   end
    #   # TODO
    # end
  end

  def am()
    maybe %w(start startservice) do
      return
    end
  end

  def dumpsys()
    maybe take_service do
      return
    end
  end

  # label "cmd" do
  #   # TODO: This would have to always run the command. Hmm.
  #   maybe take_service do
  #     finish
  #   end
  #   maybe "activity" do
  #     jump("am")
  #   end
  #   maybe "package" do
  #     jump("pm")
  #   end
  # end

  # label "dumpsys" do
  #   maybe take_service do
  #     finish
  #   end
  # end

  # label "am" do
  #   maybe %w(start startservice) do
  #     finish
  #   end
  # end

  # label "dumpsys-activity" do
  # end

  # label "pm" do
  # end

  # label "dumpsys-package" do
  # end
end

=begin
$ adb
Android Debug Bridge version 1.0.39
Version 26.0.0 rc1-eng.omakot.20170828.085512
Installed as /usr/local/google/omakoto/disk6/oc-mr1-dev/out/host/linux-x86/bin/adb

global options:
 -a         listen on all network interfaces, not just localhost
 -d         use USB device (error if multiple devices connected)
 -e         use TCP/IP device (error if multiple TCP/IP devices available)
 -s SERIAL  use device with given serial (overrides $ANDROID_SERIAL)
 -H         name of adb server host [default=localhost]
 -P         port of adb server [default=5037]
 -L SOCKET  listen on given socket for adb server [default=tcp:localhost:5037]

general commands:
 devices [-l]             list connected devices (-l for long output)
 help                     show this help message
 version                  show version num

networking:
 connect HOST[:PORT]      connect to a device via TCP/IP [default port=5555]
 disconnect [HOST[:PORT]]
     disconnect from given TCP/IP device [default port=5555], or all
 forward --list           list all forward socket connections
 forward [--no-rebind] LOCAL REMOTE
     forward socket connection using:
       tcp:<port> (<local> may be "tcp:0" to pick any open port)
       localabstract:<unix domain socket name>
       localreserved:<unix domain socket name>
       localfilesystem:<unix domain socket name>
       dev:<character device name>
       jdwp:<process pid> (remote only)
 forward --remove LOCAL   remove specific forward socket connection
 forward --remove-all     remove all forward socket connections
 ppp TTY [PARAMETER...]   run PPP over USB
 reverse --list           list all reverse socket connections from device
 reverse [--no-rebind] REMOTE LOCAL
     reverse socket connection using:
       tcp:<port> (<remote> may be "tcp:0" to pick any open port)
       localabstract:<unix domain socket name>
       localreserved:<unix domain socket name>
       localfilesystem:<unix domain socket name>
 reverse --remove REMOTE  remove specific reverse socket connection
 reverse --remove-all     remove all reverse socket connections from device

file transfer:
 push [--sync] LOCAL... REMOTE
     copy local files/directories to device
     --sync: only push files that are newer on the host than the device
 pull [-a] REMOTE... LOCAL
     copy files/dirs from device
     -a: preserve file timestamp and mode
 sync [system|vendor|oem|data|all]
     sync a local build from $ANDROID_PRODUCT_OUT to the device (default all)
     -l: list but don't copy

shell:
 shell [-e ESCAPE] [-n] [-Tt] [-x] [COMMAND...]
     run remote shell command (interactive shell if no command given)
     -e: choose escape character, or "none"; default '~'
     -n: don't read from stdin
     -T: disable PTY allocation
     -t: force PTY allocation
     -x: disable remote exit codes and stdout/stderr separation
 emu COMMAND              run emulator console command

app installation:
 install [-lrtsdg] PACKAGE
 install-multiple [-lrtsdpg] PACKAGE...
     push package(s) to the device and install them
     -l: forward lock application
     -r: replace existing application
     -t: allow test packages
     -s: install application on sdcard
     -d: allow version code downgrade (debuggable packages only)
     -p: partial application install (install-multiple only)
     -g: grant all runtime permissions
 uninstall [-k] PACKAGE
     remove this app package from the device
     '-k': keep the data and cache directories

backup/restore:
   to show usage run "adb shell bu help"

debugging:
 bugreport [PATH]
     write bugreport to given PATH [default=bugreport.zip];
     if PATH is a directory, the bug report is saved in that directory.
     devices that don't support zipped bug reports output to stdout.
 jdwp                     list pids of processes hosting a JDWP transport
 logcat                   show device log (logcat --help for more)

security:
 disable-verity           disable dm-verity checking on userdebug builds
 enable-verity            re-enable dm-verity checking on userdebug builds
 keygen FILE
     generate adb public/private key; private key stored in FILE,
     public key stored in FILE.pub (existing files overwritten)

scripting:
 wait-for[-TRANSPORT]-STATE
     wait for device to be in the given state
     State: device, recovery, sideload, or bootloader
     Transport: usb, local, or any [default=any]
 get-state                print offline | bootloader | device
 get-serialno             print <serial-number>
 get-devpath              print <device-path>
 remount
     remount /system, /vendor, and /oem partitions read-write
 reboot [bootloader|recovery|sideload|sideload-auto-reboot]
     reboot the device; defaults to booting system image but
     supports bootloader and recovery too. sideload reboots
     into recovery and automatically starts sideload mode,
     sideload-auto-reboot is the same but reboots after sideloading.
 sideload OTAPACKAGE      sideload the given full OTA package
 root                     restart adbd with root permissions
 unroot                   restart adbd without root permissions
 usb                      restart adb server listening on USB
 tcpip PORT               restart adb server listening on TCP on PORT

internal debugging:
 start-server             ensure that there is a server running
 kill-server              kill the server if it is running
 reconnect                kick connection from host side to force reconnect
 reconnect device         kick connection from device side to force reconnect
 reconnect offline        reset offline/unauthorized devices to force reconnect

environment variables:
 $ADB_TRACE
     comma-separated list of debug info to log:
     all,adb,sockets,packets,rwx,usb,sync,sysdeps,transport,jdwp
 $ADB_VENDOR_KEYS         colon-separated list of keys (files or directories)
 $ANDROID_SERIAL          serial number to connect to (see -s)
 $ANDROID_LOG_TAGS        tags to be used by logcat (see logcat --help)

================================================================================
Usage: logcat [options] [filterspecs]
options include:
  -s              Set default filter to silent. Equivalent to filterspec '*:S'
  -f <file>, --file=<file>               Log to file. Default is stdout
  -r <kbytes>, --rotate-kbytes=<kbytes>
                  Rotate log every kbytes. Requires -f option
  -n <count>, --rotate-count=<count>
                  Sets max number of rotated logs to <count>, default 4
  --id=<id>       If the signature id for logging to file changes, then clear
                  the fileset and continue
  -v <format>, --format=<format>
                  Sets log print format verb and adverbs, where <format> is:
                    brief help long process raw tag thread threadtime time
                  and individually flagged modifying adverbs can be added:
                    color descriptive epoch monotonic printable uid
                    usec UTC year zone
                  Multiple -v parameters or comma separated list of format and
                  format modifiers are allowed.
  -D, --dividers  Print dividers between each log buffer
  -c, --clear     Clear (flush) the entire log and exit
                  if Log to File specified, clear fileset instead
  -d              Dump the log and then exit (don't block)
  -e <expr>, --regex=<expr>
                  Only print lines where the log message matches <expr>
                  where <expr> is a regular expression
  -m <count>, --max-count=<count>
                  Quit after printing <count> lines. This is meant to be
                  paired with --regex, but will work on its own.
  --print         Paired with --regex and --max-count to let content bypass
                  regex filter but still stop at number of matches.
  -t <count>      Print only the most recent <count> lines (implies -d)
  -t '<time>'     Print most recent lines since specified time (implies -d)
  -T <count>      Print only the most recent <count> lines (does not imply -d)
  -T '<time>'     Print most recent lines since specified time (not imply -d)
                  count is pure numerical, time is 'MM-DD hh:mm:ss.mmm...'
                  'YYYY-MM-DD hh:mm:ss.mmm...' or 'sssss.mmm...' format
  -g, --buffer-size                      Get the size of the ring buffer.
  -G <size>, --buffer-size=<size>
                  Set size of log ring buffer, may suffix with K or M.
  -L, --last      Dump logs from prior to last reboot
  -b <buffer>, --buffer=<buffer>         Request alternate ring buffer, 'main',
                  'system', 'radio', 'events', 'crash', 'default' or 'all'.
                  Multiple -b parameters or comma separated list of buffers are
                  allowed. Buffers interleaved. Default -b main,system,crash.
  -B, --binary    Output the log in binary.
  -S, --statistics                       Output statistics.
  -p, --prune     Print prune white and ~black list. Service is specified as
                  UID, UID/PID or /PID. Weighed for quicker pruning if prefix
                  with ~, otherwise weighed for longevity if unadorned. All
                  other pruning activity is oldest first. Special case ~!
                  represents an automatic quicker pruning for the noisiest
                  UID as determined by the current statistics.
  -P '<list> ...', --prune='<list> ...'
                  Set prune white and ~black list, using same format as
                  listed above. Must be quoted.
  --pid=<pid>     Only prints logs from the given pid.
  --wrap          Sleep for 2 hours or when buffer about to wrap whichever
                  comes first. Improves efficiency of polling by providing
                  an about-to-wrap wakeup.

filterspecs are a series of
  <tag>[:priority]

where <tag> is a log component tag (or * for all) and priority is:
  V    Verbose (default for <tag>)
  D    Debug (default for '*')
  I    Info
  W    Warn
  E    Error
  F    Fatal
  S    Silent (suppress all output)

'*' by itself means '*:D' and <tag> by itself means <tag>:V.
If no '*' filterspec or -s on command line, all filter defaults to '*:V'.
eg: '*:S <tag>' prints only <tag>, '<tag>:S' suppresses all <tag> log messages.

If not specified on the command line, filterspec is set from ANDROID_LOG_TAGS.

If not specified with -v on command line, format is set from ANDROID_PRINTF_LOG
or defaults to "threadtime"

================================================================================
Activity manager (activity) commands:
  help
      Print this help text.
  start-activity [-D] [-N] [-W] [-P <FILE>] [--start-profiler <FILE>]
          [--sampling INTERVAL] [--streaming] [-R COUNT] [-S]
          [--track-allocation] [--user <USER_ID> | current] <INTENT>
      Start an Activity.  Options are:
      -D: enable debugging
      -N: enable native debugging
      -W: wait for launch to complete
      --start-profiler <FILE>: start profiler and send results to <FILE>
      --sampling INTERVAL: use sample profiling with INTERVAL microseconds
          between samples (use with --start-profiler)
      --streaming: stream the profiling output to the specified file
          (use with --start-profiler)
      -P <FILE>: like above, but profiling stops when app goes idle
      --attach-agent <agent>: attach the given agent before binding
      -R: repeat the activity launch <COUNT> times.  Prior to each repeat,
          the top activity will be finished.
      -S: force stop the target app before starting the activity
      --track-allocation: enable tracking of object allocations
      --user <USER_ID> | current: Specify which user to run as; if not
          specified then run as the current user.
      --stack <STACK_ID>: Specify into which stack should the activity be put.
  start-service [--user <USER_ID> | current] <INTENT>
      Start a Service.  Options are:
      --user <USER_ID> | current: Specify which user to run as; if not
          specified then run as the current user.
  start-foreground-service [--user <USER_ID> | current] <INTENT>
      Start a foreground Service.  Options are:
      --user <USER_ID> | current: Specify which user to run as; if not
          specified then run as the current user.
  stop-service [--user <USER_ID> | current] <INTENT>
      Stop a Service.  Options are:
      --user <USER_ID> | current: Specify which user to run as; if not
          specified then run as the current user.
  broadcast [--user <USER_ID> | all | current] <INTENT>
      Send a broadcast Intent.  Options are:
      --user <USER_ID> | all | current: Specify which user to send to; if not
          specified then send to all users.
      --receiver-permission <PERMISSION>: Require receiver to hold permission.
  instrument [-r] [-e <NAME> <VALUE>] [-p <FILE>] [-w]
          [--user <USER_ID> | current]
          [--no-window-animation] [--abi <ABI>] <COMPONENT>
      Start an Instrumentation.  Typically this target <COMPONENT> is in the
      form <TEST_PACKAGE>/<RUNNER_CLASS> or only <TEST_PACKAGE> if there
      is only one instrumentation.  Options are:
      -r: print raw results (otherwise decode REPORT_KEY_STREAMRESULT).  Use with
          [-e perf true] to generate raw output for performance measurements.
      -e <NAME> <VALUE>: set argument <NAME> to <VALUE>.  For test runners a
          common form is [-e <testrunner_flag> <value>[,<value>...]].
      -p <FILE>: write profiling data to <FILE>
      -m: Write output as protobuf (machine readable)
      -w: wait for instrumentation to finish before returning.  Required for
          test runners.
      --user <USER_ID> | current: Specify user instrumentation runs in;
          current user if not specified.
      --no-window-animation: turn off window animations while running.
      --abi <ABI>: Launch the instrumented process with the selected ABI.
          This assumes that the process supports the selected ABI.
  trace-ipc [start|stop] [--dump-file <FILE>]
      Trace IPC transactions.
      start: start tracing IPC transactions.
      stop: stop tracing IPC transactions and dump the results to file.
      --dump-file <FILE>: Specify the file the trace should be dumped to.
  profile [start|stop] [--user <USER_ID> current] [--sampling INTERVAL]
          [--streaming] <PROCESS> <FILE>
      Start and stop profiler on a process.  The given <PROCESS> argument
        may be either a process name or pid.  Options are:
      --user <USER_ID> | current: When supplying a process name,
          specify user of process to profile; uses current user if not specified.
      --sampling INTERVAL: use sample profiling with INTERVAL microseconds
          between samples
      --streaming: stream the profiling output to the specified file
  dumpheap [--user <USER_ID> current] [-n] [-g] <PROCESS> <FILE>
      Dump the heap of a process.  The given <PROCESS> argument may
        be either a process name or pid.  Options are:
      -n: dump native heap instead of managed heap
      -g: force GC before dumping the heap
      --user <USER_ID> | current: When supplying a process name,
          specify user of process to dump; uses current user if not specified.
  set-debug-app [-w] [--persistent] <PACKAGE>
      Set application <PACKAGE> to debug.  Options are:
      -w: wait for debugger when application starts
      --persistent: retain this value
  clear-debug-app
      Clear the previously set-debug-app.
  set-watch-heap <PROCESS> <MEM-LIMIT>
      Start monitoring pss size of <PROCESS>, if it is at or
      above <HEAP-LIMIT> then a heap dump is collected for the user to report.
  clear-watch-heap
      Clear the previously set-watch-heap.
  bug-report [--progress | --telephony]
      Request bug report generation; will launch a notification
        when done to select where it should be delivered. Options are:
     --progress: will launch a notification right away to show its progress.
     --telephony: will dump only telephony sections.
  force-stop [--user <USER_ID> | all | current] <PACKAGE>
      Completely stop the given application package.
  crash [--user <USER_ID>] <PACKAGE|PID>
      Induce a VM crash in the specified package or process
  kill [--user <USER_ID> | all | current] <PACKAGE>
      Kill all processes associated with the given application.
  kill-all
      Kill all processes that are safe to kill (cached, etc).
  make-uid-idle [--user <USER_ID> | all | current] <PACKAGE>
      If the given application's uid is in the background and waiting to
      become idle (not allowing background services), do that now.
  monitor [--gdb <port>]
      Start monitoring for crashes or ANRs.
      --gdb: start gdbserv on the given port at crash/ANR
  watch-uids [--oom <uid>
      Start watching for and reporting uid state changes.
      --oom: specify a uid for which to report detailed change messages.
  hang [--allow-restart]
      Hang the system.
      --allow-restart: allow watchdog to perform normal system restart
  restart
      Restart the user-space system.
  idle-maintenance
      Perform idle maintenance now.
  screen-compat [on|off] <PACKAGE>
      Control screen compatibility mode of <PACKAGE>.
  package-importance <PACKAGE>
      Print current importance of <PACKAGE>.
  to-uri [INTENT]
      Print the given Intent specification as a URI.
  to-intent-uri [INTENT]
      Print the given Intent specification as an intent: URI.
  to-app-uri [INTENT]
      Print the given Intent specification as an android-app: URI.
  switch-user <USER_ID>
      Switch to put USER_ID in the foreground, starting
      execution of that user if it is currently stopped.
  get-current-user
      Returns id of the current foreground user.
  start-user <USER_ID>
      Start USER_ID in background if it is currently stopped;
      use switch-user if you want to start the user in foreground
  unlock-user <USER_ID> [TOKEN_HEX]
      Attempt to unlock the given user using the given authorization token.
  stop-user [-w] [-f] <USER_ID>
      Stop execution of USER_ID, not allowing it to run any
      code until a later explicit start or switch to it.
      -w: wait for stop-user to complete.
      -f: force stop even if there are related users that cannot be stopped.
  is-user-stopped <USER_ID>
      Returns whether <USER_ID> has been stopped or not.
  get-started-user-state <USER_ID>
      Gets the current state of the given started user.
  track-associations
      Enable association tracking.
  untrack-associations
      Disable and clear association tracking.
  get-uid-state <UID>
      Gets the process state of an app given its <UID>.
  attach-agent <PROCESS> <FILE>
    Attach an agent to the specified <PROCESS>, which may be either a process name or a PID.
  get-config
      Rtrieve the configuration and any recent configurations of the device.
  supports-multiwindow
      Returns true if the device supports multiwindow.
  supports-split-screen-multi-window
      Returns true if the device supports split screen multiwindow.
  suppress-resize-config-changes <true|false>
      Suppresses configuration changes due to user resizing an activity/task.
  set-inactive [--user <USER_ID>] <PACKAGE> true|false
      Sets the inactive state of an app.
  get-inactive [--user <USER_ID>] <PACKAGE>
      Returns the inactive state of an app.
  send-trim-memory [--user <USER_ID>] <PROCESS>
          [HIDDEN|RUNNING_MODERATE|BACKGROUND|RUNNING_LOW|MODERATE|RUNNING_CRITICAL|COMPLETE]
      Send a memory trim event to a <PROCESS>.  May also supply a raw trim int level.
  display [COMMAND] [...]: sub-commands for operating on displays.
       move-stack <STACK_ID> <DISPLAY_ID>
           Move <STACK_ID> from its current display to <DISPLAY_ID>.
  stack [COMMAND] [...]: sub-commands for operating on activity stacks.
       start <DISPLAY_ID> <INTENT>
           Start a new activity on <DISPLAY_ID> using <INTENT>
       move-task <TASK_ID> <STACK_ID> [true|false]
           Move <TASK_ID> from its current stack to the top (true) or
           bottom (false) of <STACK_ID>.
       resize <STACK_ID> <LEFT,TOP,RIGHT,BOTTOM>
           Change <STACK_ID> size and position to <LEFT,TOP,RIGHT,BOTTOM>.
       resize-animated <STACK_ID> <LEFT,TOP,RIGHT,BOTTOM>
           Same as resize, but allow animation.
       resize-docked-stack <LEFT,TOP,RIGHT,BOTTOM> [<TASK_LEFT,TASK_TOP,TASK_RIGHT,TASK_BOTTOM>]
           Change docked stack to <LEFT,TOP,RIGHT,BOTTOM>
           and supplying temporary different task bounds indicated by
           <TASK_LEFT,TOP,RIGHT,BOTTOM>
       size-docked-stack-test: <STEP_SIZE> <l|t|r|b> [DELAY_MS]
           Test command for sizing docked stack by
           <STEP_SIZE> increments from the side <l>eft, <t>op, <r>ight, or <b>ottom
           applying the optional [DELAY_MS] between each step.
       move-top-activity-to-pinned-stack: <STACK_ID> <LEFT,TOP,RIGHT,BOTTOM>
           Moves the top activity from
           <STACK_ID> to the pinned stack using <LEFT,TOP,RIGHT,BOTTOM> for the
           bounds of the pinned stack.
       positiontask <TASK_ID> <STACK_ID> <POSITION>
           Place <TASK_ID> in <STACK_ID> at <POSITION>
       list
           List all of the activity stacks and their sizes.
       info <STACK_ID>
           Display the information about activity stack <STACK_ID>.
       remove <STACK_ID>
           Remove stack <STACK_ID>.
  task [COMMAND] [...]: sub-commands for operating on activity tasks.
       lock <TASK_ID>
           Bring <TASK_ID> to the front and don't allow other tasks to run.
       lock stop
           End the current task lock.
       resizeable <TASK_ID> [0|1|2|3]
           Change resizeable mode of <TASK_ID> to one of the following:
           0: unresizeable
           1: crop_windows
           2: resizeable
           3: resizeable_and_pipable
       resize <TASK_ID> <LEFT,TOP,RIGHT,BOTTOM>
           Makes sure <TASK_ID> is in a stack with the specified bounds.
           Forces the task to be resizeable and creates a stack if no existing stack
           has the specified bounds.
       drag-task-test <TASK_ID> <STEP_SIZE> [DELAY_MS]
           Test command for dragging/moving <TASK_ID> by
           <STEP_SIZE> increments around the screen applying the optional [DELAY_MS]
           between each step.
       size-task-test <TASK_ID> <STEP_SIZE> [DELAY_MS]
           Test command for sizing <TASK_ID> by <STEP_SIZE>
           increments within the screen applying the optional [DELAY_MS] between
           each step.
  update-appinfo <USER_ID> <PACKAGE_NAME> [<PACKAGE_NAME>...]
      Update the ApplicationInfo objects of the listed packages for <USER_ID>
      without restarting any processes.
  write
      Write all pending state to storage.

<INTENT> specifications include these flags and arguments:
    [-a <ACTION>] [-d <DATA_URI>] [-t <MIME_TYPE>]
    [-c <CATEGORY> [-c <CATEGORY>] ...]
    [-e|--es <EXTRA_KEY> <EXTRA_STRING_VALUE> ...]
    [--esn <EXTRA_KEY> ...]
    [--ez <EXTRA_KEY> <EXTRA_BOOLEAN_VALUE> ...]
    [--ei <EXTRA_KEY> <EXTRA_INT_VALUE> ...]
    [--el <EXTRA_KEY> <EXTRA_LONG_VALUE> ...]
    [--ef <EXTRA_KEY> <EXTRA_FLOAT_VALUE> ...]
    [--eu <EXTRA_KEY> <EXTRA_URI_VALUE> ...]
    [--ecn <EXTRA_KEY> <EXTRA_COMPONENT_NAME_VALUE>]
    [--eia <EXTRA_KEY> <EXTRA_INT_VALUE>[,<EXTRA_INT_VALUE...]]
        (mutiple extras passed as Integer[])
    [--eial <EXTRA_KEY> <EXTRA_INT_VALUE>[,<EXTRA_INT_VALUE...]]
        (mutiple extras passed as List<Integer>)
    [--ela <EXTRA_KEY> <EXTRA_LONG_VALUE>[,<EXTRA_LONG_VALUE...]]
        (mutiple extras passed as Long[])
    [--elal <EXTRA_KEY> <EXTRA_LONG_VALUE>[,<EXTRA_LONG_VALUE...]]
        (mutiple extras passed as List<Long>)
    [--efa <EXTRA_KEY> <EXTRA_FLOAT_VALUE>[,<EXTRA_FLOAT_VALUE...]]
        (mutiple extras passed as Float[])
    [--efal <EXTRA_KEY> <EXTRA_FLOAT_VALUE>[,<EXTRA_FLOAT_VALUE...]]
        (mutiple extras passed as List<Float>)
    [--esa <EXTRA_KEY> <EXTRA_STRING_VALUE>[,<EXTRA_STRING_VALUE...]]
        (mutiple extras passed as String[]; to embed a comma into a string,
         escape it using "\,")
    [--esal <EXTRA_KEY> <EXTRA_STRING_VALUE>[,<EXTRA_STRING_VALUE...]]
        (mutiple extras passed as List<String>; to embed a comma into a string,
         escape it using "\,")
    [-f <FLAG>]
    [--grant-read-uri-permission] [--grant-write-uri-permission]
    [--grant-persistable-uri-permission] [--grant-prefix-uri-permission]
    [--debug-log-resolution] [--exclude-stopped-packages]
    [--include-stopped-packages]
    [--activity-brought-to-front] [--activity-clear-top]
    [--activity-clear-when-task-reset] [--activity-exclude-from-recents]
    [--activity-launched-from-history] [--activity-multiple-task]
    [--activity-no-animation] [--activity-no-history]
    [--activity-no-user-action] [--activity-previous-is-top]
    [--activity-reorder-to-front] [--activity-reset-task-if-needed]
    [--activity-single-top] [--activity-clear-task]
    [--activity-task-on-home]
    [--receiver-registered-only] [--receiver-replace-pending]
    [--receiver-foreground] [--receiver-no-abort]
    [--receiver-include-background]
    [--selector]
    [<URI> | <PACKAGE> | <COMPONENT>]
================================================================================
usage: pm path [--user USER_ID] PACKAGE
       pm dump PACKAGE
       pm install [-lrtsfd] [-i PACKAGE] [--user USER_ID] [PATH]
       pm install-create [-lrtsfdp] [-i PACKAGE] [-S BYTES]
               [--install-location 0/1/2]
               [--force-uuid internal|UUID]
       pm install-write [-S BYTES] SESSION_ID SPLIT_NAME [PATH]
       pm install-commit SESSION_ID
       pm install-abandon SESSION_ID
       pm uninstall [-k] [--user USER_ID] [--versionCode VERSION_CODE] PACKAGE
       pm set-installer PACKAGE INSTALLER
       pm move-package PACKAGE [internal|UUID]
       pm move-primary-storage [internal|UUID]
       pm clear [--user USER_ID] PACKAGE
       pm enable [--user USER_ID] PACKAGE_OR_COMPONENT
       pm disable [--user USER_ID] PACKAGE_OR_COMPONENT
       pm disable-user [--user USER_ID] PACKAGE_OR_COMPONENT
       pm disable-until-used [--user USER_ID] PACKAGE_OR_COMPONENT
       pm default-state [--user USER_ID] PACKAGE_OR_COMPONENT
       pm set-user-restriction [--user USER_ID] RESTRICTION VALUE
       pm hide [--user USER_ID] PACKAGE_OR_COMPONENT
       pm unhide [--user USER_ID] PACKAGE_OR_COMPONENT
       pm grant [--user USER_ID] PACKAGE PERMISSION
       pm revoke [--user USER_ID] PACKAGE PERMISSION
       pm reset-permissions
       pm set-app-link [--user USER_ID] PACKAGE {always|ask|never|undefined}
       pm get-app-link [--user USER_ID] PACKAGE
       pm set-install-location [0/auto] [1/internal] [2/external]
       pm get-install-location
       pm set-permission-enforced PERMISSION [true|false]
       pm trim-caches DESIRED_FREE_SPACE [internal|UUID]
       pm create-user [--profileOf USER_ID] [--managed] [--restricted] [--ephemeral] [--guest] USER_NAME
       pm remove-user USER_ID
       pm get-max-users

NOTE: 'pm list' commands have moved! Run 'adb shell cmd package'
  to display the new commands.

pm path: print the path to the .apk of the given PACKAGE.

pm dump: print system state associated with the given PACKAGE.

pm install: install a single legacy package
pm install-create: create an install session
    -l: forward lock application
    -r: replace existing application
    -t: allow test packages
    -i: specify the installer package name
    -s: install application on sdcard
    -f: install application on internal flash
    -d: allow version code downgrade (debuggable packages only)
    -p: partial application install
    -g: grant all runtime permissions
    -S: size in bytes of entire session

pm install-write: write a package into existing session; path may
  be '-' to read from stdin
    -S: size in bytes of package, required for stdin

pm install-commit: perform install of fully staged session
pm install-abandon: abandon session

pm set-installer: set installer package name

pm uninstall: removes a package from the system. Options:
    -k: keep the data and cache directories around after package removal.

pm clear: deletes all data associated with a package.

pm enable, disable, disable-user, disable-until-used, default-state:
  these commands change the enabled state of a given package or
  component (written as "package/class").

pm grant, revoke: these commands either grant or revoke permissions
    to apps. The permissions must be declared as used in the app's
    manifest, be runtime permissions (protection level dangerous),
    and the app targeting SDK greater than Lollipop MR1.

pm reset-permissions: revert all runtime permissions to their default state.

pm get-install-location: returns the current install location.
    0 [auto]: Let system decide the best location
    1 [internal]: Install on internal device storage
    2 [external]: Install on external media

pm set-install-location: changes the default install location.
  NOTE: this is only intended for debugging; using this can cause
  applications to break and other undersireable behavior.
    0 [auto]: Let system decide the best location
    1 [internal]: Install on internal device storage
    2 [external]: Install on external media

pm trim-caches: trim cache files to reach the given free space.

pm create-user: create a new user with the given USER_NAME,
  printing the new user identifier of the user.

pm remove-user: remove the user with the given USER_IDENTIFIER,
  deleting all data associated with that user







=end

# This makes ruby happy with the last line
def __END_RUBY_CODE__; end
__END_RUBY_CODE__
