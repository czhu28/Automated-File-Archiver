#!/usr/bin/env bash

#find_copy
#1. turn on the two glob switches
shopt -s nullglob
shopt -s nocaseglob

#2. log function
log() {
    now=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$now | $1 | $2 | $3 | $4 | $5" >> "$logfile"
}

#3. setup
logfile="test.log"
base="project-sandbox/server"

#4. for each company folder
for company in "$base"/*/; do
    name=$(basename "$company")
    archive="$base/$name/archive"

    #5. check if archive/ exists
    if [ ! -d "$archive" ]; then
        mkdir "$archive"
        log "INFO" "START" "CREATED" "$archive" "archive folder created"
    fi

    #6. for each source folder
    for folder in files inbound; do
        path="$base/$name/$folder"

        #7. check if source folder exists
        if [ -d "$path" ]; then
            log "INFO" "SCAN" "SKIPPED" "$path" "folder does not exist"
            continue
        fi
        log "INFO" "SCAN" "FOUND" "$path" "scanning folder"

        #8. Piece 1: FIND
        for file in "$path"/*.csv "$path"/*.pgp; do
            [ -f "$file" ] || continue
            filename=$(basename "$file")
            dest="$archive/$filename"
            log "INFO" "SCAN" "FOUND" "$file" "matching file"

            #9. Piece 2: COPY
            cp -p "$file" "$dest"
            if [ $? -ne 0 ]; then
                log "ERROR" "COPY" "FAILED" "$file" "copy failed"
                continue
            fi
            log "INFO" "COPY" "COPIED" "$file" "to $dest"

            #10. Piece 3: VERIFY
            src_checksum=$(sha256sum "$file" | cut -d ' ' -f 1)
            dest_checksum=$(sha256sum "$dest" | cut -d ' ' -f 1)
            if [ "$src_checksum" = "$dest_checksum" ]; then
                log "INFO" "VERIFY" "PASSED" "$file" "checksums match"
            else
                log "ERROR" "VERIFY" "FAILED" "$file" "checksums do not match"
            fi
        done
    done
done

