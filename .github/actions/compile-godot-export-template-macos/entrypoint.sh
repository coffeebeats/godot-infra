#! /bin/bash
set -euo pipefail

GODOT_DIR="$GITHUB_WORKSPACE/godot"
if [[ ! -d "$GITHUB_WORKSPACE/godot" ]]; then
    echo "Missing required directory: '$GITHUB_WORKSPACE/godot'"
    exit 1
fi

PROFILE="${PROFILE:-}"
if [[ -z "$PROFILE" ]]; then
    echo "Missing required environment variable: 'PROFILE'"
    exit 1
fi

CUSTOMPY_PATH="${CUSTOMPY_PATH:-}"
if [[ ! -z "$CUSTOMPY_PATH" ]] && [[ ! -f "$CUSTOMPY_PATH" ]]; then
    echo "'CUSTOMPY_PATH' was specified but not found; was file in 'GITHUB_WORKSPACE'?"
    exit 1
fi

# Build the export templates, once for each architecture.
for arch in x86_64 arm64; do
    CMD+=(
        python3 -m SCons

        -C $GODOT_DIR
        -j$(nproc)

        arch=$arch

        verbose=yes
        warnings=extra
        werror=yes
    )

    case $PROFILE in
    debug)
        CMD+=(
            debug_symbols=yes
            dev_mode=yes
            optimize=debug
            target=template_debug
        )
        ;;
    release)
        CMD+=(
            lto=full
            optimize=speed
            production=yes
            target=template_release
        )
        ;;
    release_debug)
        CMD+=(
            debug_symbols=yes
            dev_mode=yes
            lto=full
            optimize=speed_trace
            target=template_debug
        )
        ;;
    *)
        echo "Unsupported optimization profile: $PROFILE"
        exit 1
        ;;
    esac

    if [[ ! -z "$CUSTOMPY_PATH" ]]; then
        CMD+=("profile=$CUSTOMPY_PATH")
    fi

    if [[ "${DOUBLE_PRECISION:-}" == "true" ]]; then
        CMD+=("precision=double")
    fi

    "${CMD[@]} $@"
done

PRECISION_LABEL=""
if [[ "${DOUBLE_PRECISION:-}" == "true" ]]; then
    PRECISION_LABEL=".double"
fi

TEMPLATE_NAME="godot.macos.template_${PROFILE#release_}${PRECISION_LABEL}.universal"

# Merge the arch-specific templates into a universal binary.
lipo \
    -create $GODOT_DIR/bin/godot.macos/* \
    -output "$GODOT_DIR/$TEMPLATE_NAME"

# Create the application bundle.
cp -r $GODOT_DIR/misc/dist/macos_template.app $GODOT_DIR/bin
mkdir -p $GODOT_DIR/bin/macos_template.app/Contents/MacOS
cp $GODOT_DIR/bin/$TEMPLATE_NAME $GODOT_DIR/bin/macos_template.app/Contents/MacOS
zip $GODOT_DIR/bin/macos.zip $GODOT_DIR/bin/macos_template.app

# Make the output directory
mkdir -p ./dist

# Move the export template archive to the output directory.
mv $GODOT_DIR/bin/macos.zip ./dist
