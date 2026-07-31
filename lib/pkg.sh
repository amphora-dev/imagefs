#!/usr/bin/env bash
# =============================================================================
# lib/pkg.sh — lightweight Buildroot-inspired package helpers
#
# Concepts borrowed from Buildroot (kept tiny, bash-only):
#   - STAGING_DIR  : cross-compile sysroot (headers + libs)  [= ROOTFS]
#   - TARGET_DIR   : runtime rootfs that becomes imagefs.txz
#   - HOST_DIR     : host tools (do not mix into target /usr)
#   - DEPENDS      : declared in packages/depends.conf
#   - content stamp: recipe + deps stamps + toolchain fingerprint
# =============================================================================

# ---- load depends.conf into PKG_DEPS[<name>]="dep1 dep2" ----
pkg_load_depends() {
    local conf="${1:-$SCRIPT_DIR/packages/depends.conf}"
    declare -gA PKG_DEPS=()
    [ -f "$conf" ] || {
        warn "depends.conf missing: $conf"
        return 0
    }
    local line name deps
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        case "$line" in
            *:*)
                name="${line%%:*}"
                name="$(echo "$name" | sed 's/[[:space:]]*$//')"
                deps="${line#*:}"
                deps="$(echo "$deps" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                PKG_DEPS["$name"]="$deps"
                ;;
        esac
    done < "$conf"
}

pkg_deps_of() {
    echo "${PKG_DEPS[$1]:-}"
}

# Expand selected packages with transitive DEPENDS (order not sorted yet).
pkg_expand_with_deps() {
    declare -A seen=()
    local queue=("$@") out=()
    local pkg dep
    while [ ${#queue[@]} -gt 0 ]; do
        pkg="${queue[0]}"
        queue=("${queue[@]:1}")
        [ -n "${seen[$pkg]:-}" ] && continue
        seen["$pkg"]=1
        out+=("$pkg")
        for dep in $(pkg_deps_of "$pkg"); do
            [ -n "$dep" ] || continue
            [ -n "${seen[$dep]:-}" ] && continue
            queue+=("$dep")
        done
    done
    printf '%s\n' "${out[@]}"
}

# Kahn topo-sort over a package set. Falls back to ALL_PACKAGES order.
pkg_topo_sort() {
    local -a wanted=("$@")
    declare -A want=()
    local p
    for p in "${wanted[@]}"; do want["$p"]=1; done

    declare -A indeg=()
    declare -A edges=() # pkg -> "dep1 dep2" restricted to wanted set
    for p in "${wanted[@]}"; do
        indeg["$p"]=0
    done
    for p in "${wanted[@]}"; do
        local deps=() d
        for d in $(pkg_deps_of "$p"); do
            [ -n "${want[$d]:-}" ] || continue
            deps+=("$d")
            indeg["$p"]=$(( ${indeg[$p]} + 1 ))
        done
        edges["$p"]="${deps[*]:-}"
    done

    local -a queue=() sorted=()
    # Seed queue in ALL_PACKAGES order for stability.
    for p in "${ALL_PACKAGES[@]}"; do
        [ -n "${want[$p]:-}" ] || continue
        [ "${indeg[$p]}" -eq 0 ] && queue+=("$p")
    done
    for p in "${wanted[@]}"; do
        [ -n "${want[$p]:-}" ] || continue
        local already=0 q
        for q in "${queue[@]}"; do [ "$q" = "$p" ] && already=1 && break; done
        [ "$already" -eq 0 ] && [ "${indeg[$p]}" -eq 0 ] && queue+=("$p")
    done

    while [ ${#queue[@]} -gt 0 ]; do
        p="${queue[0]}"
        queue=("${queue[@]:1}")
        sorted+=("$p")
        # Reduce indegree of packages that depend on p.
        local other deps
        for other in "${wanted[@]}"; do
            deps="${edges[$other]:-}"
            case " $deps " in
                *" $p "*)
                    indeg["$other"]=$(( ${indeg[$other]} - 1 ))
                    if [ "${indeg[$other]}" -eq 0 ]; then
                        queue+=("$other")
                    fi
                    ;;
            esac
        done
    done

    if [ ${#sorted[@]} -ne ${#wanted[@]} ]; then
        error "dependency cycle detected among: ${wanted[*]}"
        return 1
    fi
    printf '%s\n' "${sorted[@]}"
}

# Toolchain / layout fingerprint — changing these invalidates all stamps.
pkg_env_fingerprint() {
    printf 'arch=%s api=%s ndk=%s\n' "$ARCH" "$ANDROID_API" "${NDK_VERSION:-}"
    printf 'cflags=%s\n' "${CFLAGS:-}"
    printf 'cxxflags=%s\n' "${CXXFLAGS:-}"
    printf 'ldflags=%s\n' "${LDFLAGS:-}"
    printf 'prefix=%s\n' "${PREFIX:-}"
    printf 'staging=%s host=%s target=%s\n' \
        "${STAGING_DIR:-}" "${HOST_DIR:-}" "${TARGET_DIR:-}"
}

# Content stamp for a package: recipe + depends.conf line + dep stamps + env.
pkg_content_stamp() {
    local package="$1"
    local script="$SCRIPT_DIR/packages/${package}.sh"
    local conf="$SCRIPT_DIR/packages/depends.conf"
    {
        echo "package=$package"
        echo "depends=$(pkg_deps_of "$package")"
        sha256sum "$script" 2>/dev/null || echo "missing-script"
        # Pin depends.conf line for this package (not the whole file — avoids
        # unrelated dep edits busting every stamp).
        grep -E "^${package}[[:space:]]*:" "$conf" 2>/dev/null || true
        local dep
        for dep in $(pkg_deps_of "$package"); do
            if [ -f "$BUILT_DIR/${dep}.done" ]; then
                echo "dep:$dep=$(cat "$BUILT_DIR/${dep}.done")"
            else
                echo "dep:$dep=MISSING"
            fi
        done
        pkg_env_fingerprint
    } | sha256sum | awk '{print $1}'
}

pkg_stamp_path() {
    echo "$BUILT_DIR/${1}.done"
}

pkg_is_up_to_date() {
    local package="$1"
    local marker stamp
    marker="$(pkg_stamp_path "$package")"
    [ -f "$marker" ] || return 1
    stamp="$(pkg_content_stamp "$package")"
    [ "$(cat "$marker" 2>/dev/null)" = "$stamp" ]
}

pkg_write_stamp() {
    local package="$1"
    mkdir -p "$BUILT_DIR"
    pkg_content_stamp "$package" > "$(pkg_stamp_path "$package")"
}

# Packages that must rebuild because a dependency stamp changed / is missing.
pkg_needs_rebuild() {
    local package="$1"
    pkg_is_up_to_date "$package" && return 1
    return 0
}
