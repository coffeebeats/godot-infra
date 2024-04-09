# container

This package defines the `godot-infra` build container used to compile Godot and export projects.

## **Example usage**

### **Compiling a Godot export template**

To build Godot export templates with the `godot-infra` container, run the command below:

```sh
PLATFORM=; \
PROFILE=release; \
SCRIPT_AES256_ENCRYPTION_KEY=; \
docker run \
    --user=1000:1000 \
    -v $PWD/dist:/home/ubuntu/godot-infra/dist:Z \
    -v $PWD/.scons:/home/ubuntu/godot-infra/.scons:Z \
    -v $PWD/example:/home/ubuntu/godot-infra/project:ro,Z \
    $([[ -d "$GDENV_HOME" ]] && echo "-v $(realpath $GDENV_HOME):/home/ubuntu/godot-infra/.gdenv:Z") \
    $([[ -d "$GDBUILD_HOME" ]] && echo "-v $(realpath $GDBUILD_HOME):/home/ubuntu/godot-infra/.gdbuild:Z") \
    -e SCONS_CACHE=/home/ubuntu/godot-infra/.scons \
    -e SCRIPT_AES256_ENCRYPTION_KEY=$SCRIPT_AES256_ENCRYPTION_KEY \
    localhost/godot-infra:latest gdbuild template \
        --$PROFILE \
        --verbose \
        --out /home/ubuntu/godot-infra/dist \
        --project /home/ubuntu/godot-infra/project \
        $PLATFORM
```

### **Exporting a Godot project**

To export a Godot project target with the `godot-infra` container, run the command below:

```sh
TARGET=; \
PLATFORM=macos; \
PROFILE=release; \
SCRIPT_AES256_ENCRYPTION_KEY=; \
docker run \
    --user=1000:1000 \
    -v $PWD/dist:/home/ubuntu/godot-infra/dist:Z \
    -v $PWD/example:/home/ubuntu/godot-infra/project:Z \
    $([[ -d "$GDENV_HOME" ]] && echo "-v $(realpath $GDENV_HOME):/home/ubuntu/godot-infra/.gdenv:Z") \
    $([[ -d "$GDPACK_HOME" ]] && echo "-v $(realpath $GDPACK_HOME):/home/ubuntu/godot-infra/.gdpack:Z") \
    $([[ -d "$GDBUILD_HOME" ]] && echo "-v $(realpath $GDBUILD_HOME):/home/ubuntu/godot-infra/.gdbuild:Z") \
    -e SCRIPT_AES256_ENCRYPTION_KEY=$SCRIPT_AES256_ENCRYPTION_KEY \
    localhost/godot-infra:latest gdbuild target \
        --$PROFILE \
        --verbose \
        --out /home/ubuntu/godot-infra/dist \
        --project /home/ubuntu/godot-infra/project \
        --platform $PLATFORM \
        $TARGET
```

## **Development**

### **Setup**

The following instructions outline how to get the project set up for local development:

1. Manually run the `package-macos-sdk.yml` workflow and place the packaged `macOS` SDK into the `thirdparty/osxcross/tarballs` directory.
2. Manually run the `package-moltenvk-sdk.yaml` workflow and extract the packaged `MoltenVK` SDK into `thirdparty/moltenvk`.
3. Run the `container/build.sh` script from the repository root:

    ```sh
    LLVM_VERSION=17 \                                                                                                                                                                                      10:59:38 AM
    MACOS_VERSION=14 \
    MACOS_VERSION_MINIMUM=10.13 \
    OSXCROSS_SDK=darwin23 \
    GDENV_VERSION=0.6.19 \
    GDPACK_VERSION=0.2.10 \
    GDBUILD_VERSION=0.3.19 \
    ./container/build.sh \
        --base "docker.io/library/ubuntu:mantic"
    ```
