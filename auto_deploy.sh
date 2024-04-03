#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

SCRIPT=`basename $0`
LOCK=/tmp/${SCRIPT}_${APP}.lock

[ -f $LOCK ] && exit
touch $LOCK

APP=$1
BRANCH=$2
REPO=$3

WORKFLOW_STATUS_SCRIPT=${SCRIPT_DIR}/get_latest_action_status.rb 

source /home/${APP}/.profile &> /dev/null

LAST_TIMESTAMP=/home/$APP/.autodeploy

BUNDLE_LOG=/tmp/$$.bundle.log
DB_LOG=/tmp/$$.db.log
ASSETS_LOG=/tmp/$$.assets.log
STATUS=/tmp/$$.status.log
LOG=/tmp/${SCRIPT}_${APP}.log
echo > $LOG

cd /home/${APP}/${APP}

workflow_run=`$WORKFLOW_STATUS_SCRIPT $REPO $BRANCH`
conclusion=`echo $workflow_run | cut -d' ' -f2`
run_time=`echo $workflow_run | cut -d' ' -f1`
run_unixtime=`date "+%s" -d "$run_time"`
last_run=`cat $LAST_TIMESTAMP` 
time_diff=`expr $run_unixtime - $last_run`

if [ $time_diff -lt 60 ] ; then
  echo "Detected no new workflow run. Nothing to do." >> $LOG
  [ -f $LOCK ] && rm $LOCK
  exit
fi

if [ "$conclusion" == "success" ] ; then
  echo "New workflow run was successful." >> $LOG

  git_status=`git fetch 2>/dev/null && git status 2>/dev/null`

  up_to_date=`git fetch 2>/dev/null && git status 2>/dev/null|grep 'is up to date'`
  if [ "$up_to_date" != "" ]; then
    echo "No new changes detected. Abort." >> $LOG
    echo $run_unixtime > $LAST_TIMESTAMP
    [ -f $LOCK ] && rm $LOCK
    exit
  fi

  ok_to_pull=`git fetch 2>/dev/null && git status 2>/dev/null|grep 'can be fast-forwarded'`
  if [ "$ok_to_pull" == "" ]; then
    echo $git_status >> $LOG
    echo "It does not look safe to pull new changes. Abort." >> $LOG
    [ -f $LOCK ] && rm $LOCK
    exit
  fi

  changes=`git pull origin $BRANCH 2>/dev/null|grep Already`
  if [ "$changes" != "Already up to date." ]; then

    echo $changes >> $LOG

    echo "Deploying new changes ..." >> $LOG

    RAILS_ENV=production bundle install &> $BUNDLE_LOG
    bundle_failed=$?
    RAILS_ENV=production bundle exec rake db:migrate &> $DB_LOG
    db_failed=$?
    RAILS_ENV=production bundle exec rake assets:precompile &> $ASSETS_LOG
    assets_failed=$?

    if [ $bundle_failed -eq 1 ]; then
      cat $BUNDLE_LOG
    fi

    if [ $db_failed -eq 1 ]; then
      cat $DB_LOG
    fi

    if [ $assets_failed -eq 1 ]; then
      diff $DB_LOG $ASSETS_LOG
      diff_errors=$?
      if [ $diff_errors -eq 1 ]; then
        cat $ASSETS_LOG
      fi
    fi

    if [ $bundle_failed -eq 0 ] && [ $db_failed -eq 0 ] && [ $assets_failed -eq 0 ]; then 
      sudo systemctl stop etd-qa &> /dev/null
      sudo systemctl start etd-qa &> /dev/null
      sleep 30
      sudo systemctl status etd-qa 2>/dev/null > $STATUS
      started=`cat $STATUS | grep Listening`
      if [ "$started" != "" ]; then
        echo "New changes deployed successfully."
        echo
        cat $STATUS
        echo $run_unixtime > $LAST_TIMESTAMP
      else
        echo "Service failed to start after git pull."
        echo
        cat $STATUS
      fi 
    fi
  fi
else
  echo $workflow_run >> $LOG
  echo "GHA Workflow did not complete successfully. Nothing to do." >> $LOG
fi

[ -f $BUNDLE_LOG ] && rm $BUNDLE_LOG
[ -f $DB_LOG ] && rm $DB_LOG
[ -f $ASSETS_LOG ] && rm $ASSETS_LOG
[ -f $STATUS ] && rm $STATUS
[ -f $LOCK ] && rm $LOCK
