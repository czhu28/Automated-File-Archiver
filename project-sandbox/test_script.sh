# ---------- Log function (define once, at the top) ----------
log() {
    now=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$now | $1 | $2 | $3 | $4 | $5" >> "$logfile"
}

# ---------- Setup ----------
logfile="test.log"
base="project-sandbox/server"

# ---------- For each company folder ----------
for company in "$base"/*/; do
    name=$(basename "$company")

    # ---------- archive/ exists? ----------
    archive="$base/$name/archive"
   if [ ! -d "$archive" ]; then
       mkdir "$archive"
       log "INFO" "START" "CREATED" "$archive" "archive folder created"
   else
       log "INFO" "START" "FOUND" "$archive" "archive folder exists, reusing it"
   fi

    # ---------- For each source folder ----------
    for folder in files inbound; do
        path="$base/$name/$folder"

        # ---------- Folder exists? ----------
        if [ -d "$path" ]; then
            log "INFO" "SCAN" "FOUND" "$path" "scanning folder"
        else
            log "INFO" "SCAN" "SKIPPED" "$path" "folder does not exist"
        fi
    done
done
