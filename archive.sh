#!/usr/bin/env bash
# =====================================================================
# archive.sh : copies .csv and .pgp files from each company's
#              files/ and inbound/ folders into its archive/ folder,
#              verifies each copy by checksum and logs every step.
#
# Usage:
#   bash archive.sh <base folder>              all companies
#   bash archive.sh <base folder> <company>    one company only
#
# Examples:
#   bash archive.sh project-sandbox/server
#   bash archive.sh project-sandbox/server CompanyA
#
# Exit status: 0 = no errors, 1 = at least one ERROR, 2 = wrong usage
# =====================================================================

# ---------- Settings ----------
COMPANY_LOG="archive_run.log"   # one per company, inside archive/
SOURCE_FOLDERS="files inbound"  # folders to scan, in this order

# ---------- Check the input ----------
base="$1"
only_company="$2"

if [ -z "$base" ]; then
    echo "Usage: bash archive.sh <base folder> [company]"
    exit 2
fi
if [ ! -d "$base" ]; then
    echo "ERROR: base folder not found: $base"
    exit 2
fi
if [ -n "$only_company" ] && [ ! -d "$base/$only_company" ]; then
    echo "ERROR: company folder not found: $base/$only_company"
    exit 2
fi

# A pattern that matches nothing becomes an empty list instead of
# the literal text (e.g. "*/"). Keeps empty folders from breaking loops.
shopt -s nullglob

# ---------- Counters for the end-of-run summary ----------
total_copied=0
total_skipped=0
total_warnings=0
total_errors=0

# =====================================================================
# Helper functions
# =====================================================================

# log LEVEL STAGE ACTION PATH DETAIL  -> one line in the company log
log() {
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$now | $1 | $2 | $3 | $4 | $5" >> "$logfile"
}

# file_log LOGPATH LEVEL STAGE ACTION PATH DETAIL  -> one line in a per-file log
file_log() {
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$now | $2 | $3 | $4 | $5 | $6" >> "$1"
}

# checksum FILE  -> prints only the SHA-256 code
checksum() {
    sha256sum "$1" | cut -d' ' -f1
}

# copy_and_verify SOURCE DEST
# Copies with cp -p, checks the copy succeeded, then compares checksums.
# A bad copy is renamed to .failed and the copy is retried once.
# Returns 0 if the final copy is verified, 1 if not.
copy_and_verify() {
    local src="$1" dest="$2" flog="$2.log"
    local attempt msg status

    for attempt in 1 2; do
        # ---- Copy with cp -p ----
        msg=$(cp -p "$src" "$dest" 2>&1)
        status=$?

        # ---- Copy command succeeded? ----
        if [ $status -ne 0 ]; then
            log "ERROR" "COPY" "FAILED" "$src" "cmd=cp -p, exit=$status, msg=$msg"
            file_log "$flog" "ERROR" "COPY" "FAILED" "$src" "cmd=cp -p, exit=$status, msg=$msg"
            [ -e "$dest" ] && mv -f "$dest" "$dest.failed"
            return 1
        fi
        log "INFO" "COPY" "COPIED" "$src" "to $dest"
        file_log "$flog" "INFO" "COPY" "COPIED" "$src" "to $dest"

        # ---- Verify: checksums match? ----
        if [ "$(checksum "$src")" = "$(checksum "$dest")" ]; then
            log "INFO" "VERIFY" "VERIFIED" "$dest" "checksums match"
            file_log "$flog" "INFO" "VERIFY" "VERIFIED" "$dest" "checksums match"
            return 0
        fi

        # ---- Checksums differ: rename to .failed ----
        mv -f "$dest" "$dest.failed"
        log "ERROR" "VERIFY" "FAILED" "$dest" "checksum mismatch, attempt $attempt, renamed to $(basename "$dest").failed"
        file_log "$flog" "ERROR" "VERIFY" "FAILED" "$dest" "checksum mismatch, attempt $attempt"
        # ---- Already retried? If not, the loop runs once more ----
    done
    return 1
}

# =====================================================================
# Main: for each company folder
# =====================================================================
if [ -n "$only_company" ]; then
    companies=("$base/$only_company/")
else
    companies=("$base"/*/)
fi

for company_dir in "${companies[@]}"; do
    company=$(basename "$company_dir")
    company_dir="$base/$company"
    archive="$company_dir/archive"
    logfile="$archive/$COMPANY_LOG"
    copied=0; skipped=0; warnings=0; errors=0

    # ---------- archive/ exists? ----------
    if [ ! -d "$archive" ]; then
        msg=$(mkdir "$archive" 2>&1)
        status=$?
        # ---------- Created OK? ----------
        if [ $status -ne 0 ]; then
            # No archive/ means no company log, so report in the terminal
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR | START | FAILED | $archive | cmd=mkdir, exit=$status, msg=$msg (company skipped)"
            total_errors=$((total_errors + 1))
            continue                     # -> Next company
        fi
        log "INFO" "START" "CREATED" "$archive" "archive folder created"
    fi
    log "INFO" "START" "OPENED" "$company_dir" "checking company"

    # ---------- For each source folder ----------
    sources_found=0
    for folder in $SOURCE_FOLDERS; do
        path="$company_dir/$folder"

        # ---------- Folder exists? ----------
        if [ ! -d "$path" ]; then
            log "INFO" "SCAN" "SKIPPED" "$path" "folder does not exist"
            continue                     # -> Next folder
        fi
        sources_found=$((sources_found + 1))
        log "INFO" "SCAN" "FOUND" "$path" "scanning folder"

        # ---------- Scan top level for .csv / .pgp, any case ----------
        matches=0
        while IFS= read -r -d '' src; do
            matches=$((matches + 1))
            name=$(basename "$src")
            log "INFO" "SCAN" "FOUND" "$src" "matching file"

            # ---------- Zero bytes? ----------
            if [ ! -s "$src" ]; then
                log "WARNING" "CHECK" "SKIPPED" "$src" "zero-byte file, not archived"
                warnings=$((warnings + 1))
                continue                 # -> Next file
            fi

            dest="$archive/$name"

            # ---------- Same name in archive/? ----------
            if [ -e "$dest" ]; then
                # Split "clients.csv" into "clients" and "csv"
                stem="${name%.*}"
                ext="${name##*.}"

                # ---------- Checksum matches an archived version? ----------
                src_sum=$(checksum "$src")
                already=0
                for version in "$dest" "$archive/${stem}"_[0-9]*_[0-9]*."$ext"; do
                    if [ -f "$version" ] && [ "$(checksum "$version")" = "$src_sum" ]; then
                        already=1
                        break
                    fi
                done

                if [ $already -eq 1 ]; then
                    log "INFO" "CHECK" "SKIPPED" "$src" "already archived"
                    skipped=$((skipped + 1))
                    continue             # -> Next file
                fi

                # Different content: new name with date and time
                newdest="$archive/${stem}_$(date '+%Y%m%d_%H%M%S').${ext}"
                while [ -e "$newdest" ]; do   # never overwrite, even within the same second
                    sleep 1
                    newdest="$archive/${stem}_$(date '+%Y%m%d_%H%M%S').${ext}"
                done
                dest="$newdest"
                log "WARNING" "CHECK" "RENAMED" "$src" "same name, different content, saved as $(basename "$dest")"
                file_log "$dest.log" "WARNING" "CHECK" "RENAMED" "$src" "original name $name, same name as an archived file but different content"
                warnings=$((warnings + 1))
            fi

            # ---------- Copy, then verify ----------
            file_log "$dest.log" "INFO" "SCAN" "FOUND" "$src" "matching file"
            if copy_and_verify "$src" "$dest"; then
                copied=$((copied + 1))
            else
                errors=$((errors + 1))   # ERROR, move on -> Next file
            fi
        done < <(find "$path" -maxdepth 1 -type f \( -iname '*.csv' -o -iname '*.pgp' \) -print0 | sort -z)

        # ---------- Any matches? ----------
        if [ $matches -eq 0 ]; then
            log "INFO" "SCAN" "SKIPPED" "$path" "nothing to archive"
        fi
    done

    if [ $sources_found -eq 0 ]; then
        log "INFO" "SCAN" "SKIPPED" "$company_dir" "no files/ or inbound/ folder, company skipped"
    fi

    log "INFO" "END" "FINISHED" "$company_dir" "$copied copied, $skipped skipped, $warnings warnings, $errors errors"

    total_copied=$((total_copied + copied))
    total_skipped=$((total_skipped + skipped))
    total_warnings=$((total_warnings + warnings))
    total_errors=$((total_errors + errors))
done

# =====================================================================
# End-of-run summary
# =====================================================================
if [ $total_errors -eq 0 ]; then result="PASSED"; else result="FAILED"; fi
echo "Run finished: $total_copied copied, $total_skipped skipped, $total_warnings warnings, $total_errors errors -> $result"

[ $total_errors -eq 0 ] && exit 0 || exit 1
