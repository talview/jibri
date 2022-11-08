#!/usr/bin/env bash
HOST=""
S3_BUCKET=""
STORAGE_DIRECTORY="/meet-recordings/data/"
MINI_ENABLED_ORGS="" # comma seperated orgs_id
MINIO_ENDPOINT=""

# minio data to come from env.
IS_MINIO_ENABLED="no"
DEFAULT_STORAGE_TYPE=""
STORAGE_TYPE="aws"

# $1=session_name
is_minio_enabled_session()
{
  session_name=$1
  org_name=${session_name::-9}
  IFS=', ' read -r -a minio_enabled_orgs_list <<< "$MINI_ENABLED_ORGS"
  for org in "${minio_enabled_orgs_list[@]}"
  do
    if [ "$org" = "$org_name" ]; then
      IS_MINIO_ENABLED='yes'
    fi
  done
}

FILEPATH=$(find $1 -type f -name "*.mp4")
FILENAME_FULL=$(basename $FILEPATH)

SESSION_NAME=$(basename $FILEPATH | cut -d'_' -f 1)
ORG_NAME=${SESSION_NAME::-9}
S3_PATH="s3://"$S3_BUCKET$STORAGE_DIRECTORY$ORG_NAME"/"
FILENAME="$SESSION_NAME"_`date +"%Y-%m-%d-%H-%M-%S"`.mp4
mv $1/$FILENAME_FULL $1/$FILENAME
# Create mp4 from .ts files.
RECORDINGS_DIR=$1
for i in `ls $RECORDINGS_DIR/*.ts | sort -V`; do echo "file $i"; done > $RECORDINGS_DIR/tslist.txt
FFMPEG_CMD_OUTPUT=`ffmpeg -f concat -safe 0 -i $RECORDINGS_DIR/tslist.txt -c copy -bsf:a aac_adtstoasc $RECORDINGS_DIR/$FILENAME 2>&1 1>/dev/null `
echo "[FFMPEG_CMD_OUTPUT=$FFMPEG_CMD_OUTPUT]"
RETRY_SLEEP_TIMEOUT=5 # 5sec
MAX_RETRY_COUNT=3
RETRY_COUNT=1
S3_OUT=""
STARTTIME=$(date +%s)
# check if minio enabled session
if [ "$DEFAULT_STORAGE_TYPE" = "minio" ]; then
  IS_MINIO_ENABLED='yes'
else
  is_minio_enabled_session $SESSION_NAME
fi
while [ $RETRY_COUNT -le $MAX_RETRY_COUNT ]
do
  if [ $IS_MINIO_ENABLED = "yes" ]; then
    S3_OUT=$(aws --profile minio_profile --endpoint-url $MINIO_ENDPOINT s3 cp $RECORDINGS_DIR/$FILENAME $S3_PATH$FILENAME)
    STORAGE_TYPE="minio"
  else
    S3_OUT=$(aws s3 cp $RECORDINGS_DIR/$FILENAME $S3_PATH$FILENAME)
  STORAGE_TYPE="aws"
  fi

  if [ $? != 0 ]
  then
    RETRY_COUNT=`expr $RETRY_COUNT + 1`
    sleep $RETRY_SLEEP_TIMEOUT
    continue
  fi
  break
done
ENDTIME=$(date +%s)
STATUS="SUCCESS"
if [ $RETRY_COUNT -gt $MAX_RETRY_COUNT ]
then
  STATUS="FAILED"
  RETRY_COUNT=`expr $RETRY_COUNT - 1`
else
  STATUS="SUCCESS"
fi
echo "status=$STATUS , retry=$RETRY_COUNT, time=`expr $ENDTIME - $STARTTIME`sec, file=$RECORDINGS_DIR/$FILENAME"
echo $S3_OUT

FILESIZE=$(stat --printf="%s" $RECORDINGS_DIR/$FILENAME)
FILEDURATION=$(ffprobe -i $RECORDINGS_DIR/$FILENAME  -show_entries format=duration -v quiet -of csv="p=0")
#FZ=$((($FILESIZE/1024)/1024))
if test -z "$FILEDURATION"
then
  FILEDURATION=-1
fi
FILE_ST_PATH=$STORAGE_DIRECTORY$ORG_NAME"/"$FILENAME
DATA='{"file_name":"'$FILENAME'","file_storage_path":"'$FILE_ST_PATH'","duration":'$FILEDURATION',"size":'$FILESIZE',"recorder_id":"'$HOSTNAME'","storage_type":"'$STORAGE_TYPE'"}'
echo $DATA
curl -X POST -H "Content-Type: application/json" \
-d $DATA $HOST

if [ -z $1 ]
then
      echo "\$1 is empty"
else
#      mv $1 /recordings/saved/
      if [ -d /config/recordings/saved/$DIR_NAME ]
      then
        echo "exist"
        cp -rf  $1 /config/recordings/saved/$DIR_NAME/
        if [ "saved" == *"$1"* ]
        then
          echo "This is in saved folder. Maybe was already recovered :)"
        else
          rm -rf $1
        fi
      else
        echo " not exists"
        mv $1 /config/recordings/saved/
      fi
fi
exit 0
echo " exiting from the loop"