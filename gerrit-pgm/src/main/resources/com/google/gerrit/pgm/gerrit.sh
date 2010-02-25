#!/bin/sh
#
# Launch Gerrit Code Review as a daemon process.

# To get the service to restart correctly on reboot, uncomment below (3 lines):
# ========================
# chkconfig: 3 99 99
# description: Gerrit Code Review
# processname: gerrit
# ========================

# Configuration files:
#
# /etc/default/gerritcodereview
#   If it exists, sourced at the start of this script. It may perform any
#   sequence of shell commands, like setting relevant environment variables.
#
# The files will be checked for existence before being sourced.

# Configuration variables.  These may be set in /etc/default/gerritcodereview.
#
# GERRIT_SITE
#   Path of the Gerrit site to run.  $GERRIT_SITE/etc/gerrit.config
#   will be used to configure the process.
#
# GERRIT_WAR
#   Location of the gerrit.war download that we will execute.  Defaults to
#   container.war property in $GERRIT_SITE/etc/gerrit.config.
#
# NO_START
#   If set to "1" disables Gerrit from starting.
#
# START_STOP_DAEMON
#   If set to "0" disables using start-stop-daemon.  This may need to
#   be set on SuSE systems.

usage() {
    me=`basename "$0"`
    echo >&2 "Usage: $me {start|stop|restart|check|run|supervise} [-d site]"
    exit 1
}

test $# -gt 0 || usage

##################################################
# Some utility functions
##################################################
running() {
  test -f $1 || return 1
  PID=$(cat $1)
  ps -p $PID >/dev/null 2>/dev/null || return 1
  return 0
}

get_config() {
  if test -f "$GERRIT_CONFIG" ; then
    if type git >/dev/null 2>&1 ; then
      if test "x$1" = x--int ; then
        # Git might not be able to expand "8g" properly.  If it gives
        # us 0 back retry for the raw string and expand ourselves.
        #
        n=`git config --file "$GERRIT_CONFIG" --int "$2"`
        if test x0 = "x$n" ; then
          n=`git config --file "$GERRIT_CONFIG" --get "$2"`
          case "$n" in
          *g) n=`expr ${n%%g} \* 1024`m ;;
          *k) n=`expr ${n%%k} \* 1024` ;;
          *)  : ;;
          esac
        fi
        echo "$n"
      else
        git config --file "$GERRIT_CONFIG" $1 "$2"
      fi

    else
      # This is a very crude parser for the git configuration file.
      # Its not perfect but it can at least pull some basic values
      # from a reasonably standard format.
      #
      s=`echo "$2" | cut -d. -f1`
      k=`echo "$2" | cut -d. -f2`
      i=0
      while read n ; do
        case "$n" in
        '['$s']') i=1 ;;
        '['*']' ) i=0 ;;
        esac
        test $i || continue

        case "$n" in
        *[' 	']$k[' 	']*=*) : ;;
        [' 	']$k=*) : ;;
        $k[' 	']*=*) : ;;
        $k=*) : ;;
        *) continue ;;
        esac

        n=${n#*=}
        if test "x$1" = x--int ; then
          case "$n" in
          *g) n=`expr ${n%%g} \* 1024`m ;;
          *k) n=`expr ${n%%k} \* 1024` ;;
          *)  : ;;
          esac
        fi
        echo "$n" 
      done <"$GERRIT_CONFIG"
    fi
  fi
}

##################################################
# Get the action and options
##################################################

ACTION=$1
shift

while test $# -gt 0 ; do
  case "$1" in
  -d|--site-path)
    shift
    GERRIT_SITE=$1
    shift
    ;;
  -d=*)
    GERRIT_SITE=${1##-d=}
    shift
    ;;
  --site-path=*)
    GERRIT_SITE=${1##--site-path=}
    shift
    ;;

  *)
    usage
  esac
done

test -z "$NO_START" && NO_START=0
test -z "$START_STOP_DAEMON" && START_STOP_DAEMON=1

##################################################
# See if there's a default configuration file
##################################################
if test -f /etc/default/gerritcodereview ; then 
  . /etc/default/gerritcodereview
fi

##################################################
# Set tmp if not already set.
##################################################
if test -z "$TMP" ; then
  TMP=/tmp
fi
TMPJ=$TMP/j$$

##################################################
# Reasonable guess marker for a Gerrit site path.
##################################################
GERRIT_INSTALL_TRACE_FILE=etc/gerrit.config

##################################################
# Try to determine GERRIT_SITE if not set
##################################################
if test -z "$GERRIT_SITE" ; then
  GERRIT_SITE_1=`dirname "$0"`
  GERRIT_SITE_1=`dirname "$GERRIT_SITE_1"`
  if test -f "${GERRIT_SITE_1}/${GERRIT_INSTALL_TRACE_FILE}" ; then 
    GERRIT_SITE=${GERRIT_SITE_1} 
  fi
fi

##################################################
# No GERRIT_SITE yet? We're out of luck!
##################################################
if test -z "$GERRIT_SITE" ; then
    echo >&2 "** ERROR: GERRIT_SITE not set" 
    exit 1
fi

if cd "$GERRIT_SITE" ; then
  GERRIT_SITE=`pwd`
else
  echo >&2 "** ERROR: Gerrit site $GERRIT_SITE not found"
  exit 1
fi

#####################################################
# Check that Gerrit is where we think it is
#####################################################
GERRIT_CONFIG="$GERRIT_SITE/$GERRIT_INSTALL_TRACE_FILE"
test -e "$GERRIT_CONFIG" || {
   echo "** ERROR: Gerrit is not initialized in $GERRIT_SITE"
   exit 1
}
test -r "$GERRIT_CONFIG" || {
   echo "** ERROR: $GERRIT_CONFIG is not readable!"
   exit 1
}

GERRIT_PID="$GERRIT_SITE/logs/gerrit.pid"
GERRIT_RUN="$GERRIT_SITE/logs/gerrit.run"

##################################################
# Check for JAVA_HOME
##################################################
if test -z "$JAVA_HOME" ; then
  JAVA_HOME=`get_config --get container.javaHome`
fi
if test -z "$JAVA_HOME" ; then
    # If a java runtime is not defined, search the following
    # directories for a JVM and sort by version. Use the highest
    # version number.

    JAVA_LOCATIONS="\
        /usr/java \
        /usr/bin \
        /usr/local/bin \
        /usr/local/java \
        /usr/local/jdk \
        /usr/local/jre \
        /usr/lib/jvm \
        /opt/java \
        /opt/jdk \
        /opt/jre \
    "
    for N in java jdk jre ; do
      for L in $JAVA_LOCATIONS ; do
        test -d "$L" || continue 
        find $L -name "$N" ! -type d | grep -v threads | while read J ; do
          test -x "$J" || continue
          VERSION=`eval "$J" -version 2>&1`
          test $? = 0 || continue
          VERSION=`expr "$VERSION" : '.*"\(1.[0-9\.]*\)["_]'`
          test -z "$VERSION" && continue
          expr "$VERSION" \< 1.2 >/dev/null && continue
          echo "$VERSION:$J"
        done
      done
    done | sort | tail -1 >"$TMPJ"
    JAVA=`cat "$TMPJ" | cut -d: -f2`
    JVERSION=`cat "$TMPJ" | cut -d: -f1`
    rm -f "$TMPJ"

    JAVA_HOME=`dirname "$JAVA"`
    while test -n "$JAVA_HOME" \
               -a "$JAVA_HOME" != "/" \
               -a ! -f "$JAVA_HOME/lib/tools.jar" ; do
      JAVA_HOME=`dirname "$JAVA_HOME"`
    done
    test -z "$JAVA_HOME" && JAVA_HOME=

    echo "** INFO: Using $JAVA"
fi

if test -z "$JAVA" -a -n "$JAVA_HOME" ; then
  test -x $JAVA_HOME/bin/java -a ! -d $JAVA_HOME/bin/java && JAVA=$JAVA_HOME/bin/java
fi

if test -z "$JAVA" ; then
  echo >&2 "Cannot find a JRE or JDK. Please set JAVA_HOME to a >=1.6 JRE"
  exit 1
fi

#####################################################
# Add Gerrit properties to Java VM options.
#####################################################

GERRIT_OPTIONS=`get_config --get-all container.javaOptions`
if test -n "$GERRIT_OPTIONS" ; then
  JAVA_OPTIONS="$JAVA_OPTIONS $GERRIT_OPTIONS"
fi

GERRIT_MEMORY=`get_config --get container.heapLimit`
if test -n "$GERRIT_MEMORY" ; then
  JAVA_OPTIONS="$JAVA_OPTIONS -Xmx$GERRIT_MEMORY"
fi

GERRIT_FDS=`get_config --int core.packedGitOpenFiles`
test -z "$GERRIT_FDS" && GERRIT_FDS=128
GERRIT_FDS=`expr $GERRIT_FDS + $GERRIT_FDS`

GERRIT_USER=`get_config --get container.user`

#####################################################
# Configure sane ulimits for a daemon of our size.
#####################################################

ulimit -c 0            ; # core file size
ulimit -d unlimited    ; # data seg size
ulimit -f unlimited    ; # file size
ulimit -m unlimited    ; # max memory size
ulimit -n $GERRIT_FDS  ; # open files
ulimit -t unlimited    ; # cpu time
ulimit -t unlimited    ; # virtual memory

ulimit -x unlimited    2>/dev/null ; # file locks

#####################################################
# This is how the Gerrit server will be started
#####################################################

if test -z "$GERRIT_WAR" ; then
  GERRIT_WAR=`get_config --get container.war`
fi
if test -z "$GERRIT_WAR" ; then
  GERRIT_WAR="$GERRIT_SITE/bin/gerrit.war"
  test -f "$GERRIT_WAR" || GERRIT_WAR=
fi
if test -z "$GERRIT_WAR" -a -n "$GERRIT_USER" ; then
  for homedirs in /home /Users ; do
    if test -d "$homedirs/$GERRIT_USER" ; then
      GERRIT_WAR="$homedirs/$GERRIT_USER/gerrit.war"
      if test -f "$GERRIT_WAR" ; then
        break
      else
        GERRIT_WAR=
      fi
    fi
  done
fi
if test -z "$GERRIT_WAR" ; then
  echo >&2 "** ERROR: Cannot find gerrit.war (try setting gerrit.war)"
  exit 1
fi

test -z "$GERRIT_USER" && GERRIT_USER=$(whoami)
RUN_ARGS="-jar $GERRIT_WAR daemon -d $GERRIT_SITE"
if test -n "$JAVA_OPTIONS" ; then
  RUN_ARGS="$JAVA_OPTIONS $RUN_ARGS"
fi

if test -x /usr/bin/perl ; then
  # If possible, use Perl to mask the name of the process so its
  # something specific to us rather than the generic 'java' name.
  #
  RUN_EXEC=/usr/bin/perl
  RUN_Arg1=-e
  RUN_Arg2='$x=shift @ARGV;exec $x @ARGV;die $!'
  RUN_Arg3="-- $JAVA GerritCodeReview"
else
  RUN_EXEC=$JAVA
  RUN_Arg1=
  RUN_Arg2='-DGerritCodeReview=1'
  RUN_Arg3=
fi

##################################################
# Do the action
##################################################
case "$ACTION" in
  start)
    printf '%s' "Starting Gerrit Code Review: "

    if test 1 = "$NO_START" ; then 
      echo "Not starting gerrit - NO_START=1 in /etc/default/gerrit"
      exit 0
    fi

    test -z "$UID" && UID=`id -u`

    RUN_ID=$(date +%s).$$
    RUN_ARGS="$RUN_ARGS --run-id=$RUN_ID"

    if test 1 = "$START_STOP_DAEMON" && type start-stop-daemon >/dev/null 2>&1
    then
      test $UID = 0 && CH_USER="-c $GERRIT_USER"
      if start-stop-daemon -S -b $CH_USER \
         -p "$GERRIT_PID" -m \
         -d "$GERRIT_SITE" \
         -a "$RUN_EXEC" -- $RUN_Arg1 "$RUN_Arg2" $RUN_Arg3 $RUN_ARGS
      then
        : OK
      else
        rc=$?
        if test $rc = 127; then
          echo >&2 "fatal: start-stop-daemon failed"
          rc=1
        fi
        exit $rc 
      fi
    else
      if test -f "$GERRIT_PID" ; then
        if running "$GERRIT_PID" ; then
          echo "Already Running!!"
          exit 1
        else
          rm -f "$GERRIT_PID" "$GERRIT_RUN"
        fi
      fi

      if test $UID = 0 -a -n "$GERRIT_USER" ; then 
        touch "$GERRIT_PID"
        chown $GERRIT_USER "$GERRIT_PID"
        su - $GERRIT_USER -c "
          $RUN_EXEC $RUN_Arg1 '$RUN_Arg2' $RUN_Arg3 $RUN_ARGS &
          PID=\$! ;
          disown \$PID ;
          echo \$PID >\"$GERRIT_PID\""
      else
        $RUN_EXEC $RUN_Arg1 "$RUN_Arg2" $RUN_Arg3 $RUN_ARGS &
        PID=$!
        disown $PID
        echo $PID >"$GERRIT_PID"
      fi
    fi

    TIMEOUT=90  # seconds
    sleep 1
    while running "$GERRIT_PID" && test $TIMEOUT -gt 0 ; do
      if test "x$RUN_ID" = "x$(cat $GERRIT_RUN 2>/dev/null)" ; then
        echo OK
        exit 0
      fi

      sleep 2
      TIMEOUT=$(($TIMEOUT - 2))
    done

    echo FAILED
    exit 1
  ;;

  stop)
    printf '%s' "Stopping Gerrit Code Review: "

    if test 1 = "$START_STOP_DAEMON" && type start-stop-daemon >/dev/null 2>&1
    then
      start-stop-daemon -K -p "$GERRIT_PID" -s HUP 
      sleep 1
      if running "$GERRIT_PID" ; then
        sleep 3
        if running "$GERRIT_PID" ; then
          sleep 30
          if running "$GERRIT_PID" ; then
            start-stop-daemon -K -p "$GERRIT_PID" -s KILL
          fi
        fi
      fi
      rm -f "$GERRIT_PID" "$GERRIT_RUN"
      echo OK
    else
      PID=`cat "$GERRIT_PID" 2>/dev/null`
      TIMEOUT=30
      while running "$GERRIT_PID" && test $TIMEOUT -gt 0 ; do
        kill $PID 2>/dev/null
        sleep 1
        TIMEOUT=$(($TIMEOUT - 1))
      done
      test $TIMEOUT -gt 0 || kill -9 $PID 2>/dev/null
      rm -f "$GERRIT_PID" "$GERRIT_RUN"
      echo OK
    fi
  ;;

  restart)
    GERRIT_SH=$0
    if ! test -f "$GERRIT_SH" ; then
      echo >&2 "** ERROR: Cannot locate gerrit.sh"
      exit 1
    fi
    $GERRIT_SH stop $*
    sleep 5
    $GERRIT_SH start $*
  ;;

  supervise)
    #
    # Under control of daemontools supervise monitor which
    # handles restarts and shutdowns via the svc program.
    #
    exec "$RUN_EXEC" $RUN_Arg1 "$RUN_Arg2" $RUN_Arg3 $RUN_ARGS
    ;;

  run|daemon)
    echo "Running Gerrit Code Review:"

    if test -f "$GERRIT_PID" ; then
        if running "$GERRIT_PID" ; then
          echo "Already Running!!"
          exit 1
        else
          rm -f "$GERRIT_PID"
        fi
    fi

    exec "$RUN_EXEC" $RUN_Arg1 "$RUN_Arg2" $RUN_Arg3 $RUN_ARGS --console-log
  ;;

  check)
    echo "Checking arguments to Gerrit Code Review:"
    echo "  GERRIT_SITE     =  $GERRIT_SITE"
    echo "  GERRIT_CONFIG   =  $GERRIT_CONFIG"
    echo "  GERRIT_PID      =  $GERRIT_PID"
    echo "  GERRIT_WAR      =  $GERRIT_WAR"
    echo "  GERRIT_FDS      =  $GERRIT_FDS"
    echo "  GERRIT_USER     =  $GERRIT_USER"
    echo "  JAVA            =  $JAVA"
    echo "  JAVA_OPTIONS    =  $JAVA_OPTIONS"
    echo "  RUN_EXEC        =  $RUN_EXEC $RUN_Arg1 '$RUN_Arg2' $RUN_Arg3"
    echo "  RUN_ARGS        =  $RUN_ARGS"
    echo

    if test -f "$GERRIT_PID" ; then
        echo "Gerrit running pid="`cat "$GERRIT_PID"`
        exit 0
    fi
    exit 1
  ;;

  *)
    usage
  ;;
esac

exit 0
