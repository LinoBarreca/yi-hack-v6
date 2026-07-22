#!/bin/sh

# 6.0.1


get_random_tmp_file()
{
    local CNT=5
    local RND=""
    local TMP_FILE=""
    
    while : ; do
        # dd-checked: 2>/dev/null keeps dd's stats out of RND. An empty result
        # would collapse every upload onto the same temp name, so fall back to
        # the pid rather than continuing with a constant.
        RND=$(</dev/urandom tr -dc 0-9 | dd bs=$CNT count=1 2>/dev/null | sed -e 's/^0\+//' )  # dd-checked
        [ -n "$RND" ] || { echo "upload[WARN]: no random source, using pid" >&2; RND=$$; }
        TMP_FILE="/tmp/.tmpupload.$RND"
        
        [ -f $TMP_FILE ] || break
    done
    
    echo $TMP_FILE
}

get_file_from_post()
{
    local FILE=$1

    local CR=`printf '\r'`

    IFS="$CR"
    read -r delim_line
    IFS=""

    while read -r line; do
        test x"$line" = x"" && break
        test x"$line" = x"$CR" && break
    done

    cat > "$FILE"

    # We need to delete the tail of "\r\ndelim_line--\r\n"
    tail_len=$((${#delim_line} + 6))

    # Get and check file size
    filesize=`ls -l "$FILE" | awk '{print $5}'`

    # Truncate the file
    # Truncate to drop the trailing MIME boundary. Checked: a silent failure
    # leaves the boundary bytes appended to the uploaded file.
    dd of="$FILE" seek=$((filesize - tail_len)) bs=1 count=0 >/dev/null 2>&1 || \
        echo "upload[ERROR]: could not truncate $FILE, the MIME boundary is still appended" >&2
}

printf "Content-type: application/json\r\n\r\n"

# QUERY_STRING is a single file=<name> pair; split with parameter expansion.
FILE_TYPE=""
[ "${QUERY_STRING%%=*}" = "file" ] && FILE_TYPE=${QUERY_STRING#*=}
TMP_FILE=$(get_random_tmp_file)

CUT_FILE_TYPE=${FILE_TYPE%%_*}

if [[ "$CUT_FILE_TYPE" == "home" || "$CUT_FILE_TYPE" == "rootfs" ]] ; then
    # If home or rootfs image, place directly on sd card
    get_file_from_post "/tmp/sd/$FILE_TYPE"
else
    get_file_from_post $TMP_FILE

#    if [ "$FILE_TYPE" == "rtspv4__upload" ] ; then
#        7za x "$TMP_FILE" -y -o. &>/dev/null
#        
#        killall viewd rtspv4
#        
#        cp -rf rtspv4__*/* /home/yi-hack/extra/
#        rm -rf rtspv4__*
#        
#        chmod +x /home/yi-hack/extra/bin/viewd
#        chmod +x /home/yi-hack/extra/bin/rtspv4
#    else
        cp -f "$TMP_FILE" "/home/yi-hack/extra/$FILE_TYPE"
#    fi
fi

rm -f $TMP_FILE

printf "{\n"

printf "\"%s\":\"%s\"\n"  "error" "false"

printf "}"

exit 0
